-- ================================================
-- Title: Top 10 Countries by Email and Account Activity
-- Description:
--   This query combines email interaction data (sent, opened, visited)
--   with account creation data to compute engagement metrics per country.
--   It then calculates country-level totals and ranks countries by:
--     1. Total accounts created
--     2. Total emails sent
--   Finally, it selects only the top 10 countries for each metric.
-- ================================================

WITH union_email_account_metrics AS (
  -- Part 1: Email interaction metrics (sent, opened, clicked)
  SELECT
        DATE_ADD(s.date, INTERVAL es.sent_date DAY) AS date, -- Message send date (session date + offset)
        sp.country,
        ac.send_interval,
        ac.is_verified,
        ac.is_unsubscribed,
        CAST(NULL AS INT64) AS account_cnt, -- Empty value for account count
        COUNT(DISTINCT es.id_message) AS sent_msg, -- Number of unique emails sent
        COUNT(DISTINCT eo.id_message) AS open_msg, -- Number of emails opened
        COUNT(DISTINCT ev.id_message) AS visit_msg -- Number of emails leading to visit
  FROM `DA.email_sent` es
   LEFT JOIN `DA.email_open` eo USING (id_message)
    LEFT JOIN `DA.email_visit` ev USING (id_message)
     JOIN `DA.account` ac ON es.id_account = ac.id
      JOIN `DA.account_session` acs ON ac.id = acs.account_id
       JOIN `DA.session` s USING (ga_session_id)
        JOIN `DA.session_params` sp USING (ga_session_id)
  GROUP BY date, country, send_interval, is_verified, is_unsubscribed

  UNION ALL

  -- Part 2: Account creation data (without email metrics)
  SELECT
        s.date, -- Session date when the account was created
        sp.country,
        ac.send_interval,
        ac.is_verified,
        ac.is_unsubscribed,
        COUNT(DISTINCT ac.id) AS account_cnt, -- Number of accounts created
        CAST(NULL AS INT64) AS sent_msg, -- Email metrics are missing
        CAST(NULL AS INT64) AS open_msg,
        CAST(NULL AS INT64) AS visit_msg
  FROM `DA.account` ac
   JOIN `DA.account_session` acs ON ac.id = acs.account_id
    JOIN `DA.session` s USING (ga_session_id)
     JOIN `DA.session_params` sp USING (ga_session_id)
  GROUP BY date, country, send_interval, is_verified, is_unsubscribed
),


group_by_all AS ( -- Aggregate the merged data by all metrics
  SELECT
        date,
        country,
        send_interval,
        is_verified,
        is_unsubscribed,
        SUM(account_cnt) AS account_cnt,
        SUM(sent_msg) AS sent_msg,
        SUM(open_msg) AS open_msg,
        SUM(visit_msg) AS visit_msg
  FROM union_email_account_metrics
  GROUP BY date, country, send_interval, is_verified, is_unsubscribed
),


country_totals AS ( -- Compute country-level totals
  SELECT *,
  SUM(account_cnt) OVER (PARTITION BY country) AS total_country_account_cnt, -- Total accounts per country
  SUM(sent_msg) OVER (PARTITION BY country) AS total_country_sent_cnt -- Total emails sent per country
  FROM group_by_all
),


country_ranks AS ( -- Add country ranking by metrics
  SELECT *,
  DENSE_RANK() OVER (ORDER BY total_country_account_cnt DESC) AS rank_total_country_account_cnt, -- Ranking by account count
  DENSE_RANK() OVER (ORDER BY total_country_sent_cnt DESC) AS rank_total_country_sent_cnt -- Ranking by email sent
  FROM country_totals
)


-- Final output: Show only TOP-10 countries by either criterion
SELECT *
FROM country_ranks
WHERE rank_total_country_account_cnt <= 10 OR rank_total_country_sent_cnt <= 10
ORDER BY date;