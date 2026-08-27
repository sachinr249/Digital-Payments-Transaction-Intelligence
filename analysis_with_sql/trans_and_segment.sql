--==========================================
-- Segmentation and RFM feature engineering
--==========================================

-- Build the RFM feature table — for each user: Recency (days since last transaction), 
-- Frequency (transaction count), Monetary (total or avg amount).
-- Recency — how many days ago was their last transaction? (Lower = better, means still active)
-- Frequency — how many transactions have they made total? (Higher = more engaged)
-- Monetary — how much money have they spent total/on average? (Higher = more valuable)
select 
    u.user_id,
    u.signup_date,
    u.city,
    u.state,
    u.acquisition_channel,
    u.age_bucket,
    u.kyc_status,
    u.is_churned,
    
    -- Recency:
    datediff(
        (select max(t.timestamp) from transactions t where t.user_id = u.user_id and t.status = 'SUCCESS'),
        (select max(timestamp) from transactions)  -- treat latest data date as "today"
    ) * -1 as recency_days,
    
    -- Frequency:
    (select count(*) from transactions t where t.user_id = u.user_id and t.status = 'SUCCESS') as frequency,
    
    -- Monetary: 
    (select round(sum(amount), 2) from transactions t where t.user_id = u.user_id and t.status = 'SUCCESS') as total_amount,
    (select round(avg(amount), 2) from transactions t where t.user_id = u.user_id and t.status = 'SUCCESS') as avg_amount

from users u
LIMIT 25000;

-- no of users 
select count(distinct users.user_id) from users;


--===================================
-- Transaction-level data exploration
--===================================

-- transaction_id, status, network_type, device_type, payment_mode, 
-- transaction_type, amount, hour_of_day (extracted from timestamp), 
-- is_weekend (derived), merchant_category (joined from merchants)
select 
t1.transaction_id, t1.status, t1.network_type, t1.device_type, t1.payment_mode, t1.transaction_type, t1.amount,
hour(t1.timestamp) as hour_of_day,
case when weekday(t1.timestamp) in (5, 6) then 1 else 0 end as is_weekend,
coalesce(t2.category, 'P2P - No Merchant') as category
from transactions t1 
left join merchants t2 on t1.merchant_id = t2.merchant_id
limit 1000000 ;

-- number of transactions
select count(*) from transactions ;


--===============================================
-- Daily transaction volume (forcasting analysis)
--===============================================

select 
    date(timestamp) as txn_date,
    sum(amount) as total_amount,
    count(*) as txn_count
from transactions
where status = 'SUCCESS'
group by date(timestamp)
order by txn_date;







