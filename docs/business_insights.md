# QuickCart: business findings

As of 2026-10-28. Revenue = paid orders only, actuals only (decisions D8 and D13).
Queries: `sql/08_business_questions.sql`. Full output: `docs/business_answers.txt`.

| # | Question | Finding | What the business could do |
|---|---|---|---|
| 1 | Where does revenue come from? | Electronics (47.9%) and Furniture (42.9%) make 90.8% of revenue | Protect stock and supplier terms for these two categories first |
| 2 | How concentrated is it? | The top 10 customers bring 33.8% of revenue; 25 loyal customers (4+ paid orders) bring 52.8% | A loyalty programme protects most of the revenue |
| 3 | Who never buys? | 17 of 100 customers have never completed a paid order | Win-back campaign |
| 4 | Is money stuck? | 109,595 sits in pending orders (12.1% of order value) and 35,339 in failed payments | Chase pending payments; investigate why payments fail |
| 5 | What gets returned? | Office Chair (13.8%) and 4K Monitor (13.0%) have the highest refund rates, and the 4K Monitor is the top earner | Check product quality and descriptions for these two |
| 6 | Best market? | Manchester: 133,769 revenue, 11 of 12 customers paying | Use it as the model city for marketing |
| 7 | Data health | 37 clickstream rows quarantined; 181 orders (322,845 paid revenue) dated in the future and kept out of actuals | Fix event_id generation at the source; confirm the future-date rule |

**Caution:** monthly order counts are small (1 to 21 a month), so month-on-month growth swings wildly
(for example +2026.6% in January 2025). Hour-of-day and device differences are also too small to act on.
These are noise, not findings.