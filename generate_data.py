"""
Generate a realistic, production-shaped synthetic UPI/digital-payments dataset.

Design goals (why it's built this way):
- Vectorized with numpy/pandas, not row-by-row Faker calls, so it can scale
  to millions of rows in seconds instead of hours.
- Built-in realism: seasonality (weekday/weekend, hour-of-day peaks),
  regional skew across Indian cities, festival spikes, device/network-linked
  failure rates, merchant-tier effects, and a churn pattern in users -
  so the SQL/segmentation/forecasting work later has real signal to find,
  not just noise.
- Star-schema shaped (users, merchants, devices, transactions, refunds)
  so it mirrors what a real payments warehouse looks like.

Tune SCALE below to change dataset size. Defaults are sized to be a
realistic-feeling dataset (~1M transactions) while staying a
manageable download.
"""

import numpy as np
import pandas as pd
from faker import Faker
from datetime import datetime, timedelta

rng = np.random.default_rng(42)
fake = Faker("en_IN")
Faker.seed(42)

# ---------------------------------------------------------------------------
# SCALE CONFIG - change these to regenerate a bigger/smaller dataset
# ---------------------------------------------------------------------------
N_USERS = 25_000
N_MERCHANTS = 3_000
N_TRANSACTIONS = 1_000_000
START_DATE = datetime(2024, 1, 1)
END_DATE = datetime(2025, 12, 31)

OUT_DIR = "/home/claude/data"
import os
os.makedirs(OUT_DIR, exist_ok=True)

# ---------------------------------------------------------------------------
# Reference data (weighted, so distributions feel real rather than uniform)
# ---------------------------------------------------------------------------
CITIES = [
    ("Mumbai", "Maharashtra", 0.11), ("Delhi", "Delhi", 0.10),
    ("Bengaluru", "Karnataka", 0.09), ("Hyderabad", "Telangana", 0.07),
    ("Pune", "Maharashtra", 0.06), ("Chennai", "Tamil Nadu", 0.06),
    ("Kolkata", "West Bengal", 0.05), ("Ahmedabad", "Gujarat", 0.045),
    ("Jaipur", "Rajasthan", 0.035), ("Lucknow", "Uttar Pradesh", 0.035),
    ("Surat", "Gujarat", 0.03), ("Bhopal", "Madhya Pradesh", 0.03),
    ("Indore", "Madhya Pradesh", 0.03), ("Patna", "Bihar", 0.025),
    ("Kochi", "Kerala", 0.025), ("Nagpur", "Maharashtra", 0.02),
    ("Chandigarh", "Punjab", 0.02), ("Coimbatore", "Tamil Nadu", 0.02),
    ("Guwahati", "Assam", 0.015), ("Ranchi", "Jharkhand", 0.015),
]
city_names = [c[0] for c in CITIES]
city_states = {c[0]: c[1] for c in CITIES}
city_w = np.array([c[2] for c in CITIES]); city_w = city_w / city_w.sum()

MERCHANT_CATEGORIES = [
    ("Grocery", 0.16), ("Food & Dining", 0.14), ("Utilities/Bill Pay", 0.12),
    ("Fashion & Apparel", 0.09), ("Electronics", 0.07), ("Pharmacy", 0.08),
    ("Fuel", 0.06), ("Travel & Transport", 0.06), ("Entertainment", 0.05),
    ("Education", 0.04), ("Financial Services", 0.04), ("Home Services", 0.04),
    ("Kirana/Local Store", 0.05),
]
cat_names = [c[0] for c in MERCHANT_CATEGORIES]
cat_w = np.array([c[1] for c in MERCHANT_CATEGORIES]); cat_w = cat_w / cat_w.sum()

MERCHANT_TIERS = ["Enterprise", "SME", "Micro"]
tier_w = [0.10, 0.35, 0.55]  # long tail of small merchants, like real UPI

DEVICE_TYPES = ["Android", "iOS", "Web"]
device_w = [0.78, 0.19, 0.03]  # roughly matches India's smartphone OS split

NETWORK_TYPES = ["4G", "5G", "WiFi", "3G"]
network_w = [0.46, 0.30, 0.20, 0.04]

ACQUISITION_CHANNELS = ["Organic", "Referral", "Paid Ad", "Merchant Partner", "Bank Partnership"]
acq_w = [0.35, 0.22, 0.18, 0.15, 0.10]

PAYMENT_MODES = ["UPI", "Wallet", "Debit Card", "Credit Card", "Net Banking"]
mode_w = [0.62, 0.16, 0.11, 0.08, 0.03]

TXN_TYPES = ["P2P", "P2M"]  # person-to-person vs person-to-merchant

FAILURE_REASONS = [
    "Bank Server Timeout", "Insufficient Balance", "Incorrect UPI PIN",
    "Daily Limit Exceeded", "Network Error", "Beneficiary Bank Down",
    "Suspected Fraud - Blocked",
]
failure_w = [0.28, 0.20, 0.14, 0.09, 0.16, 0.08, 0.05]

KYC_STATUS = ["Full KYC", "Min KYC", "Pending"]
kyc_w = [0.72, 0.22, 0.06]

AGE_BUCKETS = ["18-24", "25-34", "35-44", "45-54", "55+"]
age_w = [0.22, 0.36, 0.24, 0.12, 0.06]

print("Generating users...")
# -----------------------------------------------------------------
# USERS
# -----------------------------------------------------------------
user_ids = np.arange(1, N_USERS + 1)
signup_days_ago = rng.integers(0, (END_DATE - START_DATE).days, size=N_USERS)
signup_dates = [START_DATE + timedelta(days=int(d)) for d in signup_days_ago]

# churn pattern: ~18% of users are "inactive" (churned) - signal for segmentation
is_churned = rng.random(N_USERS) < 0.18

users = pd.DataFrame({
    "user_id": user_ids,
    "signup_date": signup_dates,
    "city": rng.choice(city_names, size=N_USERS, p=city_w),
    "acquisition_channel": rng.choice(ACQUISITION_CHANNELS, size=N_USERS, p=acq_w),
    "age_bucket": rng.choice(AGE_BUCKETS, size=N_USERS, p=age_w),
    "kyc_status": rng.choice(KYC_STATUS, size=N_USERS, p=kyc_w),
    "is_churned": is_churned,
})
users["state"] = users["city"].map(city_states)
users = users[["user_id", "signup_date", "city", "state", "acquisition_channel",
               "age_bucket", "kyc_status", "is_churned"]]

print("Generating merchants...")
# -----------------------------------------------------------------
# MERCHANTS
# -----------------------------------------------------------------
merchant_ids = np.arange(1, N_MERCHANTS + 1)
onboard_days_ago = rng.integers(0, (END_DATE - START_DATE).days, size=N_MERCHANTS)
onboard_dates = [START_DATE + timedelta(days=int(d)) for d in onboard_days_ago]

merchants = pd.DataFrame({
    "merchant_id": merchant_ids,
    "merchant_name": [f"{fake.company()}" for _ in range(N_MERCHANTS)],
    "category": rng.choice(cat_names, size=N_MERCHANTS, p=cat_w),
    "tier": rng.choice(MERCHANT_TIERS, size=N_MERCHANTS, p=tier_w),
    "city": rng.choice(city_names, size=N_MERCHANTS, p=city_w),
    "onboarding_date": onboard_dates,
})
merchants["state"] = merchants["city"].map(city_states)

print("Generating devices (1-2 per user)...")
# -----------------------------------------------------------------
# DEVICES  (each user has 1-2 devices)
# -----------------------------------------------------------------
n_devices_per_user = rng.choice([1, 2], size=N_USERS, p=[0.82, 0.18])
device_user_ids = np.repeat(user_ids, n_devices_per_user)
n_devices = len(device_user_ids)
devices = pd.DataFrame({
    "device_id": np.arange(1, n_devices + 1),
    "user_id": device_user_ids,
    "device_type": rng.choice(DEVICE_TYPES, size=n_devices, p=device_w),
    "primary_network": rng.choice(NETWORK_TYPES, size=n_devices, p=network_w),
})

print("Generating transactions (this is the big one)...")
# -----------------------------------------------------------------
# TRANSACTIONS
# -----------------------------------------------------------------
# Skew transaction volume so power users exist (Zipf-like), and churned
# users transact far less / stop earlier - gives segmentation & retention
# analysis something real to find.
user_activity_weight = rng.pareto(a=2.0, size=N_USERS) + 0.1
user_activity_weight[users["is_churned"].values] *= 0.15
user_activity_weight = user_activity_weight / user_activity_weight.sum()

txn_user_idx = rng.choice(N_USERS, size=N_TRANSACTIONS, p=user_activity_weight)
txn_user_ids = user_ids[txn_user_idx]

txn_type = rng.choice(TXN_TYPES, size=N_TRANSACTIONS, p=[0.34, 0.66])
is_p2m = txn_type == "P2M"

merchant_weight = np.where(
    merchants["tier"].values == "Enterprise", 3.0,
    np.where(merchants["tier"].values == "SME", 1.5, 1.0)
)
merchant_weight = merchant_weight / merchant_weight.sum()
txn_merchant_idx = rng.choice(N_MERCHANTS, size=N_TRANSACTIONS, p=merchant_weight)
txn_merchant_ids = np.where(is_p2m, merchant_ids[txn_merchant_idx], -1)  # -1 = no merchant (P2P)

# --- timestamps with weekday + hour-of-day + festival-month seasonality ---
total_days = (END_DATE - START_DATE).days
day_base_weight = np.ones(total_days + 1)
dates_index = [START_DATE + timedelta(days=d) for d in range(total_days + 1)]
for i, d in enumerate(dates_index):
    # weekend bump
    if d.weekday() >= 5:
        day_base_weight[i] *= 1.25
    # festival season bump (Oct-Nov: Diwali season; Dec: year-end)
    if d.month in (10, 11):
        day_base_weight[i] *= 1.45
    if d.month == 12:
        day_base_weight[i] *= 1.2
day_base_weight = day_base_weight / day_base_weight.sum()

txn_day_idx = rng.choice(total_days + 1, size=N_TRANSACTIONS, p=day_base_weight)
txn_dates = [dates_index[i] for i in txn_day_idx]

# hour-of-day: peaks at lunch (13) and evening (19-21)
hour_weight = np.array([
    0.010,0.006,0.004,0.003,0.004,0.008,  # 0-5
    0.020,0.035,0.050,0.050,0.045,0.055,  # 6-11
    0.075,0.080,0.055,0.045,0.045,0.050,  # 12-17
    0.075,0.090,0.085,0.060,0.035,0.020,  # 18-23
])
hour_weight = hour_weight / hour_weight.sum()
txn_hours = rng.choice(24, size=N_TRANSACTIONS, p=hour_weight)
txn_minutes = rng.integers(0, 60, size=N_TRANSACTIONS)
txn_seconds = rng.integers(0, 60, size=N_TRANSACTIONS)

txn_timestamps = [
    d.replace(hour=int(h), minute=int(m), second=int(s))
    for d, h, m, s in zip(txn_dates, txn_hours, txn_minutes, txn_seconds)
]

# --- amounts: lognormal, P2M skews lower/tighter, P2P has fatter tail ---
p2m_amounts = rng.lognormal(mean=5.6, sigma=0.7, size=N_TRANSACTIONS)   # ~ INR 100-2000 typical
p2p_amounts = rng.lognormal(mean=6.3, sigma=1.0, size=N_TRANSACTIONS)   # wider spread
amounts = np.where(is_p2m, p2m_amounts, p2p_amounts)
amounts = np.round(np.clip(amounts, 10, 200_000), 2)

payment_modes = rng.choice(PAYMENT_MODES, size=N_TRANSACTIONS, p=mode_w)

# --- device/network-linked failure probability (real signal for SQL/EDA) ---
device_lookup = devices.drop_duplicates(subset="user_id", keep="first").set_index("user_id")
txn_network = device_lookup["primary_network"].reindex(txn_user_ids).fillna("4G").values
txn_device_type = device_lookup["device_type"].reindex(txn_user_ids).fillna("Android").values

base_fail_rate = 0.06
network_fail_bump = np.select(
    [txn_network == "3G", txn_network == "WiFi", txn_network == "5G"],
    [0.10, -0.01, -0.015],
    default=0.0,
)
hour_fail_bump = np.where(np.isin(txn_hours, [19, 20, 21]), 0.015, 0.0)  # peak-hour congestion
fail_prob = np.clip(base_fail_rate + network_fail_bump + hour_fail_bump, 0.01, 0.35)
is_failed = rng.random(N_TRANSACTIONS) < fail_prob
status = np.where(is_failed, "FAILED", "SUCCESS")

failure_reason = np.full(N_TRANSACTIONS, "", dtype=object)
n_failed = int(is_failed.sum())
failure_reason[is_failed] = rng.choice(FAILURE_REASONS, size=n_failed, p=failure_w)

transactions = pd.DataFrame({
    "transaction_id": np.arange(1, N_TRANSACTIONS + 1),
    "user_id": txn_user_ids,
    "merchant_id": txn_merchant_ids,
    "transaction_type": txn_type,
    "payment_mode": payment_modes,
    "amount": amounts,
    "timestamp": txn_timestamps,
    "status": status,
    "failure_reason": failure_reason,
    "device_type": txn_device_type,
    "network_type": txn_network,
})

print("Generating refunds (subset of successful P2M transactions)...")
# -----------------------------------------------------------------
# REFUNDS  (~3% of successful P2M transactions get refunded)
# -----------------------------------------------------------------
eligible = transactions[(transactions["status"] == "SUCCESS") & (transactions["transaction_type"] == "P2M")]
refund_mask = rng.random(len(eligible)) < 0.03
refund_txns = eligible[refund_mask].copy()

refund_reasons = ["Order Cancelled", "Product Return", "Duplicate Payment", "Merchant Error", "Service Not Rendered"]
refund_reason_w = [0.35, 0.25, 0.15, 0.15, 0.10]

refunds = pd.DataFrame({
    "refund_id": np.arange(1, len(refund_txns) + 1),
    "transaction_id": refund_txns["transaction_id"].values,
    "refund_amount": refund_txns["amount"].values,
    "refund_date": [
        ts + timedelta(days=int(d)) for ts, d in
        zip(refund_txns["timestamp"], rng.integers(1, 10, size=len(refund_txns)))
    ],
    "refund_reason": rng.choice(refund_reasons, size=len(refund_txns), p=refund_reason_w),
})

# ---------------------------------------------------------------------------
# Save everything
# ---------------------------------------------------------------------------
print("Writing CSVs...")
users.to_csv(f"datasets/users.csv", index=False)
merchants.to_csv(f"datasets/merchants.csv", index=False)
devices.to_csv(f"datasets/devices.csv", index=False)
transactions.to_csv(f"datasets/transactions.csv", index=False)
refunds.to_csv(f"datasets/refunds.csv", index=False)

print("\n--- Summary ---")
print(f"users:        {len(users):,} rows")
print(f"merchants:    {len(merchants):,} rows")
print(f"devices:      {len(devices):,} rows")
print(f"transactions: {len(transactions):,} rows  ({is_failed.sum():,} failed = {is_failed.mean():.1%})")
print(f"refunds:      {len(refunds):,} rows")
print("\nDone.")