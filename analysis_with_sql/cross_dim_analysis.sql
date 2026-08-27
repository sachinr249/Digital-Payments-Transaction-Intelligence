-- ========================================
-- Cross-dimensional questions and analysis
-- ========================================

-- Does the 3G failure problem hit some merchant categories harder than others?
--  e.g., if Fuel or Grocery merchants (likely low-connectivity areas) have both high 3G usage and high failure rate, 
-- that's a real infrastructure insight, not just a device stat.

with failure as (
	select  t2.category ,t1.network_type ,t1.status ,  sum(t1.value) as "no_trans"
	from (
		select merchant_id  ,network_type , status , count(*) as "value"
		from transactions t1
		where merchant_id !=-1
		group by merchant_id  ,network_type , status
		)t1
	join merchants t2 on t1.merchant_id = t2.merchant_id
	group by t2.category,network_type,status
), failure_rate as (
		select category , network_type ,status, no_trans ,sum(no_trans) over(partition by category , network_type  ) as "total_trans"
		from failure 
)
select category , network_type , round(no_trans/total_trans * 100,2) as "failure_rate"
from failure_rate
where status= "FAILED" ;


-- Is failure rate different for new users (signed up <30 days ago) vs. established users? 
-- New-to-UPI users fumbling their PIN is a very real, very common pattern — worth checking if your data shows it.
with user_info as (
	select t1.user_id , 
	t1.status , t2.signup_date , 
	case when signup_date < date_add((select max(signup_date) from users) , interval -1 month ) then "established_user" else "new_user" end as "user_type"
	from transactions t1
	join users t2 on t1.user_id = t2.user_id
	where merchant_id = -1
), user_type_info as (
	select user_type , status , count(*) as "total_trans" 
	from user_info
	group by user_type , status
) 
select t1.user_type , round(total_trans/(select sum(total_trans) from user_type_info t2 where t1.user_type = t2.user_type) * 100,1) as "failure_rate"
from user_type_info t1
where status = "FAILED" ;
    
-- Does acquisition channel predict churn, not just transaction value? 
--  now check which channel has the highest churn rate.
--  A channel could bring high-value users who churn fast, which changes the ROI story completely.
with churn_dist as (
	select acquisition_channel , is_churned , count(*) as "value"
	from users 
	group by acquisition_channel , is_churned
)
select t1.acquisition_channel , round(value/(select sum(t2.value) from churn_dist t2 where t1.acquisition_channel = t2.acquisition_channel ) *100,1) as "churn_rate" 
from churn_dist t1
where t1.is_churned = 1 ;

-- ========================================
--         Distribution questions
-- ========================================

-- What's the median transaction amount vs. the average, per category? 
-- If mean >> median in a category, that tells you a few huge outlier transactions are skewing the 
-- "average" — a classic trap in payments data (someone paying a huge one-time bill).

with ranked_data as (
select t2.category , t1.amount , 
row_number() over(partition by t2.category order by t1.amount ) as row_num,
count(*) OVER (partition by t2.category) AS total_rows
from transactions t1
join merchants t2 on t1.merchant_id = t2.merchant_id 
) 
select category ,  
round(avg(case when  row_num in (FLOOR((total_rows + 1) / 2), FLOOR((total_rows + 2) / 2)) then amount end),1) as median_trans , 
round(avg(amount),1) as mean_trans
from ranked_data t1 
group by category ;


-- What % of total transaction volume comes from the top 5% of users? 
with p_rank_data as (
	select amount , percent_rank() over(order by amount) as p_rank
	from transactions
) 
select 
round((select sum(amount) from  p_rank_data where p_rank >= 0.95)/ sum(amount) *100,1) as tras_by_top5,
round((select sum(amount) from  p_rank_data where p_rank < 0.95)/ sum(amount) *100,1) as tras_by_95
from transactions ;


-- =======================================
--       Lifecycle / trend questions
-- =======================================
-- Merchant lifecycle: do merchants onboarded more recently process less volume than older ones (ramp-up effect), or is it flat? 
-- Tells a "merchant maturity curve" story.

with cte4 as (
	select 
	case when onboarding_date < date_add((select max(onboarding_date) from merchants),interval -1 month) then "old" else "new" end as merchant_type ,
	sum(t2.amount) as trans_amount,
    datediff(max(onboarding_date),min(onboarding_date)) as days
	from merchants t1
	left join transactions t2 on t1.merchant_id = t2.merchant_id
	group by merchant_type
)
select merchant_type , round(trans_amount/days) as transaction_perday
from cte4 ;


-- First-transaction lag: how many days after signup does a user make their first transaction?
--  Is there a big drop-off of users who never transact at all (signed up, never activated)?

with trans_detail as (
	select 
	t1.user_id ,
	min(datediff(t2.timestamp , t1.signup_date))as min_trans_day 
	from users t1
	left join transactions t2 on t1.user_id = t2.user_id
	where t1.signup_date < t2.timestamp  or t2.timestamp is null                -- some of data is corrupted in transactions table as signup date must be less than any transaction
	group by t1.user_id
) 
select 
case 
	when min_trans_day is null then "never transacted"
    when min_trans_day = 0  then "same day"
    when min_trans_day <=10  then "1-10 days"
    when min_trans_day <=30  then "10-30 days"
    when min_trans_day <=50  then "30-50 days"
    when min_trans_day <= 90   then "50-90 days"
    else "90+ days"
end as bucket , 
count(*) as num_user
from trans_detail 
group by bucket
order by num_user desc ;
 
-- ================================
--    Geographic questions
-- ================================
-- State-level failure rate differences — if certain states show meaningfully higher failure rates,
--  that could point to network infrastructure gaps (real business insight, not just a data quirk).

with state_dist as (
	select  t2.state , t1.status
	from transactions t1 
	join users t2 on t2.user_id = t1.user_id 
	union all 
	select  t2.state , t1.status
	from transactions t1 
	join merchants t2 on t2.merchant_id = t1.merchant_id 
) 
select state , 
round(sum(case when status = "FAILED" then 1 else 0 end ) / count(*) *100,1) as failure_rate
from state_dist
group by state ;


-- ==============================
--    Risk-flavored questions 
-- ==============================

-- Which users have an unusually high failure rate specifically due to "Suspected Fraud - Blocked"? 
-- Isolate that one failure_reason and see if it clusters on specific devices, networks, or 
-- transaction sizes — a mini fraud-signal exploration.
select
t1.device_type , t1.primary_network , count(t2.failure_reason) as failure_by_suspectedfraud
from devices t1
join (select * from transactions where status = "FAILED") t2
on t1.user_id = t2.user_id
where failure_reason = "Suspected Fraud - Blocked"
group by t1.device_type , t1.primary_network
order by failure_by_suspectedfraud desc ;







