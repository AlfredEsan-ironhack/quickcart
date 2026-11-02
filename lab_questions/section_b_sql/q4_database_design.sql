-- q4_database_design.sql
-- Section B, Q4: normalized schemas for
--   1. shipment tracking   2. product inventory   3. customer support tickets
-- Everything lives in its own schema, lab_q4. The QuickCart pipeline schemas
-- (raw, clean, analytics, ops) are only READ, never changed.
-- No sample or test rows are inserted. The new tables start empty.
-- Remove everything with: lab_questions/section_b_sql/q4_teardown.sql

BEGIN;

DROP SCHEMA IF EXISTS lab_q4 CASCADE;
CREATE SCHEMA lab_q4;
COMMENT ON SCHEMA lab_q4 IS 'Lab answer for Section B Q4. Not part of the QuickCart pipeline.';

-- ---------------------------------------------------------------------------
-- Parent tables: copies of the REAL QuickCart customers, products and orders.
-- Why copies? The daily pipeline DROPs and rebuilds clean.customers / products /
-- orders. A foreign key pointing straight at them would block that DROP and turn
-- the clean_core task red. Pointing at copies keeps the pipeline safe.
-- ---------------------------------------------------------------------------
CREATE TABLE lab_q4.customers AS TABLE clean.customers;
ALTER TABLE lab_q4.customers ADD PRIMARY KEY (customer_id);

CREATE TABLE lab_q4.products AS TABLE clean.products;
ALTER TABLE lab_q4.products ADD PRIMARY KEY (product_id);

CREATE TABLE lab_q4.orders AS TABLE clean.orders;
ALTER TABLE lab_q4.orders ADD PRIMARY KEY (order_id);
ALTER TABLE lab_q4.orders ADD FOREIGN KEY (customer_id) REFERENCES lab_q4.customers (customer_id);
ALTER TABLE lab_q4.orders ADD FOREIGN KEY (product_id)  REFERENCES lab_q4.products (product_id);


-- ---------------------------------------------------------------------------
-- Shared building block: addresses (used by shipments and warehouses).
-- Kept in one table so city / postal code are never repeated (3NF).
-- ---------------------------------------------------------------------------
CREATE TABLE lab_q4.addresses (
    address_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    line1         TEXT    NOT NULL,
    line2         TEXT,
    city          TEXT    NOT NULL,
    postal_code   TEXT    NOT NULL,
    country_code  CHAR(2) NOT NULL
);


-- ===========================================================================
-- 1. SHIPMENT TRACKING
-- ===========================================================================
CREATE TABLE lab_q4.carriers (
    carrier_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    carrier_name  TEXT NOT NULL UNIQUE
);

-- Lookup table: a status can only be one of the listed codes (no typos).
CREATE TABLE lab_q4.shipment_statuses (
    status_code   TEXT PRIMARY KEY,
    description   TEXT NOT NULL
);

CREATE TABLE lab_q4.shipments (
    shipment_id            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    carrier_id             INTEGER NOT NULL REFERENCES lab_q4.carriers (carrier_id),
    tracking_number        TEXT    NOT NULL,
    origin_address_id      INTEGER NOT NULL REFERENCES lab_q4.addresses (address_id),
    destination_address_id INTEGER NOT NULL REFERENCES lab_q4.addresses (address_id),
    shipped_at             TIMESTAMPTZ,
    estimated_delivery     DATE,
    delivered_at           TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (carrier_id, tracking_number),                  -- unique per carrier
    CHECK (delivered_at IS NULL OR shipped_at IS NULL OR delivered_at >= shipped_at)
);

-- Link table: one parcel can hold several orders, one order can be split
-- over several parcels (many-to-many).
CREATE TABLE lab_q4.shipment_items (
    shipment_id      INTEGER NOT NULL REFERENCES lab_q4.shipments (shipment_id) ON DELETE CASCADE,
    order_id         INTEGER NOT NULL REFERENCES lab_q4.orders (order_id),
    quantity_shipped INTEGER NOT NULL CHECK (quantity_shipped > 0),
    PRIMARY KEY (shipment_id, order_id)
);

-- Append-only tracking history. The current status = the newest event.
CREATE TABLE lab_q4.shipment_events (
    event_id     BIGINT  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shipment_id  INTEGER NOT NULL REFERENCES lab_q4.shipments (shipment_id) ON DELETE CASCADE,
    status_code  TEXT    NOT NULL REFERENCES lab_q4.shipment_statuses (status_code),
    location     TEXT,
    event_ts     TIMESTAMPTZ NOT NULL,
    notes        TEXT
);

-- "Where is my order?"           -> find the parcel(s) for an order
CREATE INDEX idx_shipment_items_order ON lab_q4.shipment_items (order_id);
-- deliveries per address
CREATE INDEX idx_shipments_dest       ON lab_q4.shipments (destination_address_id);
-- "What is still on the way?"     -> only undelivered parcels are indexed (partial index)
CREATE INDEX idx_shipments_open       ON lab_q4.shipments (estimated_delivery) WHERE delivered_at IS NULL;
-- newest event of a parcel first
CREATE INDEX idx_events_shipment_ts   ON lab_q4.shipment_events (shipment_id, event_ts DESC);
-- events arrive in time order, so a tiny BRIN index is enough for date ranges
CREATE INDEX idx_events_ts_brin       ON lab_q4.shipment_events USING BRIN (event_ts);


-- ===========================================================================
-- 2. PRODUCT INVENTORY
-- ===========================================================================
CREATE TABLE lab_q4.warehouses (
    warehouse_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    warehouse_name TEXT NOT NULL UNIQUE,
    address_id     INTEGER REFERENCES lab_q4.addresses (address_id)
);

-- Current stock: exactly one row per product per warehouse.
CREATE TABLE lab_q4.inventory (
    warehouse_id       INTEGER NOT NULL REFERENCES lab_q4.warehouses (warehouse_id),
    product_id         INTEGER NOT NULL REFERENCES lab_q4.products (product_id),
    quantity_on_hand   INTEGER NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),   -- no overselling
    quantity_reserved  INTEGER NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
    reorder_level      INTEGER NOT NULL DEFAULT 0 CHECK (reorder_level >= 0),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (warehouse_id, product_id),
    CHECK (quantity_reserved <= quantity_on_hand)
);

-- Ledger: every stock change is recorded, so "why is stock 17?" can be answered.
CREATE TABLE lab_q4.inventory_movements (
    movement_id     BIGINT  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    warehouse_id    INTEGER NOT NULL REFERENCES lab_q4.warehouses (warehouse_id),
    product_id      INTEGER NOT NULL REFERENCES lab_q4.products (product_id),
    movement_type   TEXT    NOT NULL
                    CHECK (movement_type IN ('receipt', 'sale', 'return',
                                             'adjustment', 'transfer_in', 'transfer_out')),
    quantity_delta  INTEGER NOT NULL CHECK (quantity_delta <> 0),
    order_id        INTEGER REFERENCES lab_q4.orders (order_id),   -- filled for sales and returns
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- stock of one product across all warehouses
CREATE INDEX idx_inventory_product      ON lab_q4.inventory (product_id);
-- restock alerts: only the few rows at or below their reorder level (partial index)
CREATE INDEX idx_inventory_low_stock    ON lab_q4.inventory (warehouse_id, product_id)
                                        WHERE quantity_on_hand <= reorder_level;
-- movement history per product / per warehouse, newest first
CREATE INDEX idx_movements_product_ts   ON lab_q4.inventory_movements (product_id, created_at DESC);
CREATE INDEX idx_movements_warehouse_ts ON lab_q4.inventory_movements (warehouse_id, created_at DESC);
-- movements caused by an order
CREATE INDEX idx_movements_order        ON lab_q4.inventory_movements (order_id) WHERE order_id IS NOT NULL;


-- ===========================================================================
-- 3. CUSTOMER SUPPORT TICKETS
-- ===========================================================================
CREATE TABLE lab_q4.teams (
    team_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    team_name  TEXT NOT NULL UNIQUE
);

CREATE TABLE lab_q4.agents (
    agent_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    team_id    INTEGER NOT NULL REFERENCES lab_q4.teams (team_id),
    full_name  TEXT    NOT NULL,
    email      TEXT    NOT NULL UNIQUE,
    is_active  BOOLEAN NOT NULL DEFAULT TRUE
);

-- Lookup tables: categories, priorities (with their SLA) and statuses.
CREATE TABLE lab_q4.ticket_categories (
    category_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name  TEXT NOT NULL UNIQUE
);

CREATE TABLE lab_q4.ticket_priorities (
    priority_id    SMALLINT PRIMARY KEY,
    priority_name  TEXT     NOT NULL UNIQUE,
    sla_hours      INTEGER  NOT NULL CHECK (sla_hours > 0)
);

CREATE TABLE lab_q4.ticket_statuses (
    status_code    TEXT    PRIMARY KEY,
    is_open        BOOLEAN NOT NULL
);

CREATE TABLE lab_q4.tickets (
    ticket_id          INTEGER  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id        INTEGER  NOT NULL REFERENCES lab_q4.customers (customer_id),
    order_id           INTEGER  REFERENCES lab_q4.orders (order_id),     -- optional
    category_id        INTEGER  NOT NULL REFERENCES lab_q4.ticket_categories (category_id),
    priority_id        SMALLINT NOT NULL REFERENCES lab_q4.ticket_priorities (priority_id),
    status_code        TEXT     NOT NULL REFERENCES lab_q4.ticket_statuses (status_code),
    assigned_agent_id  INTEGER  REFERENCES lab_q4.agents (agent_id),
    subject            TEXT     NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at        TIMESTAMPTZ,
    CHECK (resolved_at IS NULL OR resolved_at >= created_at)
);

-- One ticket has many messages (1NF: no list of messages inside one column).
CREATE TABLE lab_q4.ticket_messages (
    message_id          BIGINT  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_id           INTEGER NOT NULL REFERENCES lab_q4.tickets (ticket_id) ON DELETE CASCADE,
    author_customer_id  INTEGER REFERENCES lab_q4.customers (customer_id),
    author_agent_id     INTEGER REFERENCES lab_q4.agents (agent_id),
    body                TEXT    NOT NULL,
    is_internal_note    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(author_customer_id, author_agent_id) <= 1)  -- never both authors
);

-- Every status change, so time-to-resolve and SLA breaches can be measured.
CREATE TABLE lab_q4.ticket_status_history (
    history_id           BIGINT  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_id            INTEGER NOT NULL REFERENCES lab_q4.tickets (ticket_id) ON DELETE CASCADE,
    old_status           TEXT    REFERENCES lab_q4.ticket_statuses (status_code),
    new_status           TEXT    NOT NULL REFERENCES lab_q4.ticket_statuses (status_code),
    changed_by_agent_id  INTEGER REFERENCES lab_q4.agents (agent_id),
    changed_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- a customer's tickets, newest first
CREATE INDEX idx_tickets_customer    ON lab_q4.tickets (customer_id, created_at DESC);
-- tickets about an order
CREATE INDEX idx_tickets_order       ON lab_q4.tickets (order_id) WHERE order_id IS NOT NULL;
-- an agent's open work queue: only unresolved tickets (partial index)
CREATE INDEX idx_tickets_agent_open  ON lab_q4.tickets (assigned_agent_id, priority_id, created_at)
                                     WHERE resolved_at IS NULL;
-- support dashboards: by status and priority
CREATE INDEX idx_tickets_status_prio ON lab_q4.tickets (status_code, priority_id, created_at);
CREATE INDEX idx_tickets_category    ON lab_q4.tickets (category_id);
-- a ticket's conversation and history in order
CREATE INDEX idx_messages_ticket     ON lab_q4.ticket_messages (ticket_id, created_at);
CREATE INDEX idx_history_ticket      ON lab_q4.ticket_status_history (ticket_id, changed_at);
CREATE INDEX idx_agents_team         ON lab_q4.agents (team_id);

-- Foreign keys on the copied orders table, indexed for joins
CREATE INDEX idx_lab_orders_customer ON lab_q4.orders (customer_id);
CREATE INDEX idx_lab_orders_product  ON lab_q4.orders (product_id);

COMMIT;

\echo 'lab_q4 built. Real rows copied into the parent tables:'
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM lab_q4.customers
UNION ALL SELECT 'products', COUNT(*) FROM lab_q4.products
UNION ALL SELECT 'orders',   COUNT(*) FROM lab_q4.orders;
