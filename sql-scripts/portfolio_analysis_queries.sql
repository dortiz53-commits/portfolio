-- Portfolio Analysis Queries
-- Advanced SQL queries for real estate portfolio management
-- Author: David Ortiz

-- 1. Portfolio Performance Dashboard Query
-- Returns key metrics for executive dashboard
SELECT 
    'Portfolio Overview' as metric_category,
    COUNT(DISTINCT p.property_id) as total_properties,
    SUM(p.square_footage) as total_square_footage,
    SUM(pv.appraised_value) as total_portfolio_value,
    AVG(fp.occupancy_rate) * 100 as avg_occupancy_pct,
    SUM(fp.net_operating_income * 12) as annual_noi,
    SUM(fp.net_operating_income * 12) / SUM(pv.appraised_value) * 100 as portfolio_cap_rate
FROM properties p
JOIN property_valuations pv ON p.property_id = pv.property_id
JOIN financial_performance fp ON p.property_id = fp.property_id
WHERE pv.valuation_date = (
    SELECT MAX(valuation_date) 
    FROM property_valuations pv2 
    WHERE pv2.property_id = p.property_id
)
AND fp.period_start = (
    SELECT MAX(period_start) 
    FROM financial_performance fp2 
    WHERE fp2.property_id = p.property_id
);

-- 2. Top Performing Properties by NOI Yield
-- Identifies highest performing properties for potential expansion
SELECT 
    p.property_id,
    p.address,
    p.city,
    p.property_type,
    p.square_footage,
    pv.appraised_value,
    fp.net_operating_income * 12 as annual_noi,
    (fp.net_operating_income * 12 / pv.appraised_value) * 100 as cap_rate,
    fp.occupancy_rate * 100 as occupancy_pct,
    (fp.net_operating_income * 12 / p.square_footage) as noi_per_sf,
    RANK() OVER (ORDER BY (fp.net_operating_income * 12 / pv.appraised_value) DESC) as performance_rank
FROM properties p
JOIN property_valuations pv ON p.property_id = pv.property_id
JOIN financial_performance fp ON p.property_id = fp.property_id
WHERE pv.valuation_date = (
    SELECT MAX(valuation_date) 
    FROM property_valuations pv2 
    WHERE pv2.property_id = p.property_id
)
AND fp.period_start = (
    SELECT MAX(period_start) 
    FROM financial_performance fp2 
    WHERE fp2.property_id = p.property_id
)
ORDER BY cap_rate DESC
LIMIT 10;

-- 3. Lease Rollover Risk Analysis
-- Critical for cash flow planning and renewal strategy
WITH lease_rollover AS (
    SELECT 
        p.property_id,
        p.address,
        p.property_type,
        YEAR(l.lease_end_date) as expiration_year,
        COUNT(l.lease_id) as leases_expiring,
        SUM(l.monthly_rent * 12) as annual_rent_at_risk,
        AVG(l.rent_per_sf) as avg_rent_per_sf,
        SUM(l.square_footage) as sf_expiring
    FROM properties p
    JOIN leases l ON p.property_id = l.property_id
    WHERE l.lease_status = 'Active'
    AND l.lease_end_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 3 YEAR)
    GROUP BY p.property_id, p.address, p.property_type, YEAR(l.lease_end_date)
)
SELECT 
    property_id,
    address,
    property_type,
    expiration_year,
    leases_expiring,
    annual_rent_at_risk,
    sf_expiring,
    avg_rent_per_sf,
    SUM(annual_rent_at_risk) OVER (PARTITION BY property_id ORDER BY expiration_year) as cumulative_rent_risk,
    ROUND(annual_rent_at_risk / SUM(annual_rent_at_risk) OVER (PARTITION BY property_id) * 100, 2) as pct_of_property_income
FROM lease_rollover
ORDER BY property_id, expiration_year;

-- 4. Market Comparison Analysis
-- Benchmarks portfolio performance against market averages
SELECT 
    p.property_type,
    p.city,
    COUNT(*) as portfolio_properties,
    AVG(fp.net_operating_income * 12 / pv.appraised_value) * 100 as portfolio_cap_rate,
    AVG(md.average_cap_rate) * 100 as market_cap_rate,
    (AVG(fp.net_operating_income * 12 / pv.appraised_value) - AVG(md.average_cap_rate)) * 100 as cap_rate_premium,
    AVG(fp.occupancy_rate) * 100 as portfolio_occupancy,
    AVG(1 - md.vacancy_rate) * 100 as market_occupancy,
    (AVG(fp.occupancy_rate) - AVG(1 - md.vacancy_rate)) * 100 as occupancy_premium,
    AVG(fp.net_operating_income * 12 / p.square_footage) as portfolio_noi_psf,
    AVG(md.average_rent_psf) as market_rent_psf
FROM properties p
JOIN property_valuations pv ON p.property_id = pv.property_id
JOIN financial_performance fp ON p.property_id = fp.property_id
JOIN market_data md ON p.property_type = md.property_type 
    AND p.city = md.city
WHERE pv.valuation_date = (
    SELECT MAX(valuation_date) 
    FROM property_valuations pv2 
    WHERE pv2.property_id = p.property_id
)
AND fp.period_start = (
    SELECT MAX(period_start) 
    FROM financial_performance fp2 
    WHERE fp2.property_id = p.property_id
)
AND md.reporting_period = (
    SELECT MAX(reporting_period) 
    FROM market_data md2 
    WHERE md2.market_name = md.market_name 
    AND md2.property_type = md.property_type
)
GROUP BY p.property_type, p.city
ORDER BY cap_rate_premium DESC;

-- 5. Cash Flow Trend Analysis
-- 12-month rolling analysis of cash flow trends
SELECT 
    p.property_id,
    p.address,
    p.property_type,
    fp.period_start,
    fp.net_operating_income,
    LAG(fp.net_operating_income, 1) OVER (PARTITION BY p.property_id ORDER BY fp.period_start) as prior_month_noi,
    LAG(fp.net_operating_income, 12) OVER (PARTITION BY p.property_id ORDER BY fp.period_start) as prior_year_noi,
    ROUND(
        (fp.net_operating_income - LAG(fp.net_operating_income, 1) OVER (PARTITION BY p.property_id ORDER BY fp.period_start)) 
        / LAG(fp.net_operating_income, 1) OVER (PARTITION BY p.property_id ORDER BY fp.period_start) * 100, 2
    ) as mom_growth_pct,
    ROUND(
        (fp.net_operating_income - LAG(fp.net_operating_income, 12) OVER (PARTITION BY p.property_id ORDER BY fp.period_start)) 
        / LAG(fp.net_operating_income, 12) OVER (PARTITION BY p.property_id ORDER BY fp.period_start) * 100, 2
    ) as yoy_growth_pct,
    AVG(fp.net_operating_income) OVER (
        PARTITION BY p.property_id 
        ORDER BY fp.period_start 
        ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    ) as rolling_12mo_avg_noi,
    fp.occupancy_rate * 100 as occupancy_pct
FROM properties p
JOIN financial_performance fp ON p.property_id = fp.property_id
WHERE fp.period_start >= DATE_SUB(CURDATE(), INTERVAL 24 MONTH)
ORDER BY p.property_id, fp.period_start DESC;

-- 6. Acquisition Target Analysis
-- Identifies potential acquisition opportunities based on market data
WITH market_opportunities AS (
    SELECT 
        md.market_name,
        md.city,
        md.state,
        md.property_type,
        md.average_cap_rate,
        md.vacancy_rate,
        md.average_rent_psf,
        md.average_sale_price_psf,
        LAG(md.average_cap_rate, 4) OVER (
            PARTITION BY md.market_name, md.property_type 
            ORDER BY md.reporting_period
        ) as cap_rate_4q_ago,
        LAG(md.vacancy_rate, 4) OVER (
            PARTITION BY md.market_name, md.property_type 
            ORDER BY md.reporting_period
        ) as vacancy_rate_4q_ago
    FROM market_data md
    WHERE md.reporting_period = (
        SELECT MAX(reporting_period) 
        FROM market_data md2 
        WHERE md2.market_name = md.market_name 
        AND md2.property_type = md.property_type
    )
)
SELECT 
    market_name,
    city,
    state,
    property_type,
    ROUND(average_cap_rate * 100, 2) as current_cap_rate,
    ROUND(cap_rate_4q_ago * 100, 2) as cap_rate_4q_ago,
    ROUND((average_cap_rate - cap_rate_4q_ago) * 100, 2) as cap_rate_change_bps,
    ROUND(vacancy_rate * 100, 2) as current_vacancy_pct,
    ROUND(vacancy_rate_4q_ago * 100, 2) as vacancy_4q_ago_pct,
    ROUND((vacancy_rate - vacancy_rate_4q_ago) * 100, 2) as vacancy_change_pct,
    average_rent_psf,
    average_sale_price_psf,
    CASE 
        WHEN average_cap_rate > 0.065 AND vacancy_rate < 0.10 THEN 'High Priority'
        WHEN average_cap_rate > 0.055 AND vacancy_rate < 0.15 THEN 'Medium Priority'
        ELSE 'Low Priority'
    END as acquisition_priority
FROM market_opportunities
WHERE cap_rate_4q_ago IS NOT NULL
ORDER BY 
    CASE 
        WHEN average_cap_rate > 0.065 AND vacancy_rate < 0.10 THEN 1
        WHEN average_cap_rate > 0.055 AND vacancy_rate < 0.15 THEN 2
        ELSE 3
    END,
    average_cap_rate DESC;

-- 7. Property Maintenance and CapEx Analysis
-- Tracks maintenance costs and identifies properties needing attention
SELECT 
    p.property_id,
    p.address,
    p.property_type,
    p.year_built,
    2025 - p.year_built as property_age,
    SUM(fp.maintenance_repairs) as total_maintenance_12mo,
    AVG(fp.maintenance_repairs) as avg_monthly_maintenance,
    SUM(fp.maintenance_repairs) / p.square_footage as maintenance_per_sf,
    SUM(fp.net_operating_income) as total_noi_12mo,
    SUM(fp.maintenance_repairs) / SUM(fp.net_operating_income) * 100 as maintenance_pct_of_noi,
    CASE 
        WHEN SUM(fp.maintenance_repairs) / p.square_footage > 5.00 THEN 'High Maintenance'
        WHEN SUM(fp.maintenance_repairs) / p.square_footage > 2.50 THEN 'Medium Maintenance'
        ELSE 'Low Maintenance'
    END as maintenance_category,
    RANK() OVER (ORDER BY SUM(fp.maintenance_repairs) / p.square_footage DESC) as maintenance_rank
FROM properties p
JOIN financial_performance fp ON p.property_id = fp.property_id
WHERE fp.period_start >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
GROUP BY p.property_id, p.address, p.property_type, p.year_built, p.square_footage
HAVING total_noi_12mo > 0
ORDER BY maintenance_per_sf DESC;

