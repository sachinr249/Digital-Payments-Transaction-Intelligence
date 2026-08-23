-- =============================
-- Tier 1 — Basic Aggergation
-- =============================

-- What's the overall transaction success rate vs. failure rate?
select ((select count(status) from transactions
					  where status = "SUCCESS"
                      )/count(status))*100
		as "Succes Rate",
        ((select count(status) from transactions
					  where status = "FAILED"
                      )/count(status))*100
		as "Failure Rate"
from transactions ;

-- What's the total and average transaction amount, split by transaction_type (P2P vs P2M)?
select transaction_type , round(sum(amount)) as Total_Amount , round(avg(amount)) as Avg_Trans_Amount from transactions
group by transaction_type ;

-- Which payment mode (UPI/Wallet/Card/Net Banking) is used most often?
select payment_mode , 
round((count(payment_mode)/(select count(payment_mode) from transactions))*100,1) as "transaction_percentage"
from transactions
group by payment_mode
order by transaction_percentage desc ;

-- How many users are marked as churned vs. active?
select case when is_churned = 1 then "churned" else "active" end as "user_type",
count(is_churned) as "users",
round(count(is_churned)/(select count(is_churned) from users)*100,1) as "users_percentage"
from users
group by is_churned ;

-- Which city/state has the highest number of registered users?
select state, city, count(user_id) as "registered_users"
from users 
group by state,city
order by registered_users desc
limit 10 ;

-- Which merchant category has the most merchants, and which has the highest total transaction volume? 
-- (These two answers might differ — that's worth noticing.)
select t1.category, count(distinct t1.merchant_id) as "total_merchants" ,sum(t2.amount) as "total_transaction_volume"
from merchants t1
join transactions t2 on t1.merchant_id = t2.merchant_id
group by t1.category
order by total_merchants desc ;

-- =========================================================
-- Tier 2 — the real "business insight"
-- =========================================================

-- Which merchant category has the highest failure rate — and does that match any category you'd expect to have flaky payments?
select t1.category , round((count(case when status="SUCCESS" then 1 end)/count(t2.status))*100,1) as "success_rate",
round((count(case when status="FAILED" then 1 end)/count(t2.status))*100,1) as "failure_rate"
from merchants t1
join transactions t2 on t1.merchant_id = t2.merchant_id
group by t1.category
order by success_rate desc ;


-- Do 3G users actually fail more often than 5G/WiFi users?
select network_type ,round((count(case when status="SUCCESS" then 1 end)/count(status))*100,1) as "success_rate"
from transactions
group by network_type
order by success_rate desc ;


-- Is there a difference in average transaction amount between Android, iOS, and Web users?
select device_type , avg(amount) as "avg_transaction"
from transactions
group by device_type
order by avg_transaction desc ;

-- Which acquisition channel brings in users with the highest average transaction value?
select 
t1.acquisition_channel, round(avg(t2.amount)) as "avg_transaction_value"
from users t1
join transactions t2 on t1.user_id = t2.user_id
group by t1.acquisition_channel
order by avg_transaction_value desc ;

-- What's the refund rate by merchant category — which category gets refunded most, and why might that be 
with category_refund_amount as (
	select 
	t1.category, round(sum(t3.refund_amount)) as "refunded_amount"
	from merchants t1
	join transactions t2 on t1.merchant_id = t2.merchant_id
	join refunds t3 on t2.transaction_id = t3.transaction_id
	group by t1.category
)
select category , round(refunded_amount/(select sum(refunded_amount) from category_refund_amount) *100,2) as "refund_rate"
from category_refund_amount ;


-- Do Enterprise-tier merchants really process more volume than SME/Micro, and by how much?
with merchant_dist as (
	select 
	merchant_id , sum(amount) as "amount"
	from transactions
    where merchant_id != -1
	group by merchant_id
), tier_dist as (
		select t2.tier , sum(t1.amount) as "total_amount"
		from merchant_dist t1
		join merchants t2 on t1.merchant_id = t2.merchant_id
		group by t2.tier
	)
select tier , round(total_amount/(select sum(total_amount) from tier_dist)*100,2) as "perc_vol_transaction"
from tier_dist ; 

-- What % of total transaction value comes from churned vs. active users? (This sets up your later segmentation work.)
select 
case when t2.is_churned = 1 then "churned" else "active" end as "user_type" , 
round((sum(t1.amount)/(select sum(amount) from transactions))*100,1) as "total_percentage_transaction"
from transactions t1
join users t2 on t1.user_id = t2.user_id
group by user_type ;

-- =========================================================
-- Tier 3 —      Window Functions + Advanced analysis
-- =========================================================

-- Running total: cumulative daily transaction volume over the two years — 
-- is growth steady or does it spike around Oct–Dec like it should?
select 
	date , 
	sum(amount) over(order by date rows between unbounded preceding and current row) as "cum_amount"
	from (
	select 
		date(timestamp) as "date", sum(amount) "amount"
		from transactions
		group by date ) t ;


-- Rank per group: for each merchant category, rank merchants by total revenue (top merchant per category)
with cte2 as (
	select category , merchant_name ,
		rank() over(partition by category order by trans_revenue desc) as "merchant_rank"
		from (
		select t1.category , t1.merchant_name , sum(t2.amount) as "trans_revenue"
		from merchants t1
		join transactions t2
		on t1.merchant_id = t2.merchant_id
		group by t1.category , t1.merchant_name )t 
)
select * from cte2
	where merchant_rank <= 5
	order by category asc, merchant_rank asc ;


-- Retention/cohort: group users by signup month, then check what % of each cohort is still transacting 30/60/90 days later
with user_activity as (
   select
	u.user_id,
	date_format(u.signup_date, '%Y-%m-01') as cohort_month,
	max(case when DATEDIFF(t.timestamp, u.signup_date) between 0 and 30 then 1 else 0 end) as active_30d,
	max(case when DATEDIFF(t.timestamp, u.signup_date) between 0 and 60 then 1 else 0 end) as  active_60d,
	max(case when DATEDIFF(t.timestamp, u.signup_date) between 0 and 90 then 1 else 0 end) as active_90d
	from users u
    left join transactions t on u.user_id = t.user_id
    where u.signup_date <= '2025-10-02'  -- for the 90-day retention column only
    group by u.user_id, cohort_month
)
select
    cohort_month,
    count(*) as cohort_size,
    round(sum(active_30d) / count(*) * 100, 1) as retention_30d_pct,
    round(sum(active_60d) / count(*) * 100, 1) as retention_60d_pct,
    round(sum(active_90d) / count(*) * 100, 1) as retention_90d_pct
from user_activity
group by cohort_month
order by cohort_month;

-- Month-over-month or day-over-day % change in transaction volume (a classic LAG() window function question)
with trans_by_month as (
	select date_format(timestamp, '%Y-%m') "month", sum(amount) as "curr_month_trans"
	from transactions
	group by date_format(timestamp, '%Y-%m')
	order by date_format(timestamp, '%Y-%m')
)
select month,
	curr_month_trans,
	lag(curr_month_trans) over(order by month) "prev_month_trans",
	round(((curr_month_trans - lag(curr_month_trans) over(order by month) ) / (lag(curr_month_trans) over(order by month) )) *100,2) as "% change"
from trans_by_month ;


-- Peak-hour congestion check: does failure rate really spike during 7–9 PM  Prove it with hour-by-hour breakdown
with failure_breakdown as (
	select
		concat(
		date_format(timestamp, '%l - '), 
		date_format(date_add(timestamp, interval 1 hour), '%l %p')
		) AS time_zone , 
	count(status) as "failures"
	from transactions
	where status = "FAILED"
	group by time_zone
	order by failures desc
)
select time_zone , round(failures/(select sum(failures) from failure_breakdown)* 100,2) as "percentage_failure_rate"
from failure_breakdown ;


-- Find users who transact very frequently but with a low average amount vs. users who transact rarely but with high amounts (early taste of the RFM segmentation you'll formalize in Python later)
WITH user_stats AS (
    SELECT 
        user_id,
        COUNT(*) AS txn_count,
        ROUND(AVG(amount), 2) AS avg_amount
    FROM transactions
    WHERE status = 'SUCCESS'
    GROUP BY user_id
),
ranked AS (
    SELECT 
        user_id,
        txn_count,
        avg_amount,
        NTILE(4) OVER (ORDER BY txn_count) AS freq_quartile,
        NTILE(4) OVER (ORDER BY avg_amount) AS amount_quartile
    FROM user_stats
)
SELECT 
    user_id,
    txn_count,
    avg_amount,
    CASE 
        WHEN freq_quartile = 4 AND amount_quartile = 1 THEN 'Frequent, Low Value'
        WHEN freq_quartile = 1 AND amount_quartile = 4 THEN 'Rare, High Value'
        WHEN freq_quartile = 4 AND amount_quartile = 4 THEN 'Frequent, High Value (VIP)'
        WHEN freq_quartile = 1 AND amount_quartile = 1 THEN 'Rare, Low Value (At Risk)'
        ELSE 'Mid-tier'
    END AS user_segment
FROM ranked
ORDER BY txn_count DESC;


