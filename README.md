# Digital Payments Transaction Intelligence & Risk Analytics

An end-to-end analytics case study on a simulated digital payments (UPI-style) platform — 
covering SQL analysis, customer segmentation, failure-risk modeling, and time-series 
forecasting on 1 million synthetic transactions.

## Why this project

Built to practice the kind of analysis a payments/fintech analyst role actually involves: 
querying large transactional data, segmenting users for business decisions, understanding 
what drives failures/risk, and forecasting volume — using SQL, Python, and Excel.

## Dataset

A realistic, production-shaped synthetic dataset (not scraped or downloaded) generated with 
a fully vectorized Python script, so it can be regenerated at any scale.

| Table | Rows | Description |
|---|---|---|
| `users` | 25,000 | Signup date, city, KYC status, acquisition channel, churn flag |
| `merchants` | 3,000 | Category, tier (Enterprise/SME/Micro), location |
| `devices` | ~29,600 | Device type and network type per user |
| `transactions` | 1,000,000 | Core fact table — amount, timestamp, status, network, payment mode |
| `refunds` | ~18,500 | Refund amount, reason, linked to original transaction |

Realistic patterns were deliberately built in — weekday/weekend and festival-season 
seasonality, a Pareto-distributed power-user base, network-linked failure rates, and a 
churn pattern — so the analysis has genuine signal to uncover, not just noise.

## Tech stack

`Python (pandas, numpy, scikit-learn, Prophet, matplotlib/seaborn)` · `MySQL` · `Excel`

## Project structure

```
├── data/
│   ├── generate_data.py        # dataset generation script (scalable)
│   ├── load_data_in_MYSQL               # load data in MySQL 
│   └── *.csv                    # generated tables
├── Analysis_with_sql/
│   ├── schema.sql        # schema
│   ├── aggregation.sql               # basic sql aggregations
│   └── cross_dim_analysis.sql                    # advance aggregations
│   ├── trans_and_segment.sql               # generated data for segemtation,failure and forecasting 
├── Segmentation_analysis/
│   ├── segmentation.ipynb       # RFM + K-Means customer segmentation
├── trans_failure_analysis/
│   ├── transaction_failure_analysis.ipynb       # chi-square testing + logistic regression
├── forecasting/
│   ├── forecasting.ipynb       # Prophet time-series forecast
├── dashboard/
│   └── rfm_dashboard.xlsx       # Excel validation report + charts of key outcomes
└── README.md
```

## 1. SQL Analysis

20+ queries against the MySQL database, ranging from basic aggregation to window 
functions (running totals, `RANK()`, `LAG()`, cohort retention with `DATEDIFF`). Covers 
success/failure rates, merchant category performance, refund rates, retention by signup 
cohort, and peak-hour failure patterns.

## 2. Customer Segmentation

Segmented all 25,000 users two independent ways, then cross-validated one against the 
other rather than trusting a single method:

- **Rule-based RFM** — Recency/Frequency/Monetary quartile scoring → VIP, At Risk, 
  Dormant, New & Promising
- **K-Means clustering** (k=4, features log-transformed to correct for right-skew)

**Result:** the two methods agree strongly at the extremes — **97–99% overlap** on VIP 
and Dormant users — giving high confidence these are real segments, not artifacts of 
arbitrary thresholds. They diverge in the middle: K-Means treats "Dormant" and "At Risk" 
as one continuous engagement gradient rather than two hard categories. Cluster centroids 
confirmed recency, frequency, and monetary value all rank in the same order across every 
cluster — engagement behaves like a spectrum, not distinct customer types.

## 3. Transaction Failure Risk

Used chi-square testing to identify which features actually relate to failure before 
modeling — most (payment mode, merchant category, device type) showed no meaningful 
relationship. **Network type and peak-hour timing** were the only features with both 
statistical and practical significance.

Built a logistic regression on the confirmed features:
- **ROC-AUC: 0.575** — modest but real predictive power
- Coefficients correctly matched the known pattern: 4G/5G/WiFi all show substantially 
  lower failure odds than 3G; peak hours (7–9 PM) increase failure risk

**Takeaway:** failure is driven meaningfully by connectivity and timing, but most of the 
variation comes from factors outside this dataset (e.g. real-time bank server issues) — 
worth using for infrastructure decisions, not as a transaction-level fraud filter.

## 4. Forecasting

Forecasted daily transaction volume using Prophet, holding out the last 45 days as a 
test set (never shuffling time-series data).

- **MAPE: 6.23%** on the 45-day holdout
- Model correctly learned the weekly transaction rhythm and the Oct–Dec festival-season 
  surge directly from historical dates, with no manual feature engineering

## Excel Dashboard

A companion Excel workbook (`dashboard/rfm_dashboard.xlsx`) presents the RFM segmentation, 
K-Means validation, and cross-tabulation results as charts and summary tables — a 
business-facing view of the same findings, for a non-technical audience.

## Key limitations

- Dataset is synthetic; patterns were built in deliberately to enable meaningful analysis, 
  not observed from real transactions
- Failure-prediction model has a real but limited ceiling (AUC 0.575), reflecting genuine 
  limits of the available features rather than a modeling shortfall
- RFM thresholds are quartile-based and somewhat arbitrary by construction — K-Means was 
  used specifically to validate them
