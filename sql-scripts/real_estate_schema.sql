-- Real Estate Investment Database Schema
-- Created for portfolio demonstration
-- Author: David Ortiz

-- Properties table - Core property information
CREATE TABLE properties (
    property_id INT PRIMARY KEY AUTO_INCREMENT,
    address VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(2) NOT NULL,
    zip_code VARCHAR(10) NOT NULL,
    property_type ENUM('Office', 'Retail', 'Industrial', 'Multifamily', 'Hotel', 'Self Storage') NOT NULL,
    square_footage INT NOT NULL,
    year_built INT NOT NULL,
    number_of_units INT DEFAULT 1,
    parking_spaces INT DEFAULT 0,
    lot_size_sf INT,
    zoning VARCHAR(50),
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Property valuations - Track property values over time
CREATE TABLE property_valuations (
    valuation_id INT PRIMARY KEY AUTO_INCREMENT,
    property_id INT NOT NULL,
    valuation_date DATE NOT NULL,
    appraised_value DECIMAL(12,2) NOT NULL,
    market_value DECIMAL(12,2),
    assessed_value DECIMAL(12,2),
    valuation_method ENUM('Appraisal', 'Market Analysis', 'Assessment', 'Internal') NOT NULL,
    appraiser_name VARCHAR(100),
    notes TEXT,
    FOREIGN KEY (property_id) REFERENCES properties(property_id),
    INDEX idx_property_date (property_id, valuation_date)
);

-- Financial performance - Monthly/quarterly financial data
CREATE TABLE financial_performance (
    performance_id INT PRIMARY KEY AUTO_INCREMENT,
    property_id INT NOT NULL,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    gross_rental_income DECIMAL(10,2) NOT NULL DEFAULT 0,
    vacancy_loss DECIMAL(10,2) NOT NULL DEFAULT 0,
    other_income DECIMAL(10,2) NOT NULL DEFAULT 0,
    operating_expenses DECIMAL(10,2) NOT NULL DEFAULT 0,
    property_taxes DECIMAL(10,2) NOT NULL DEFAULT 0,
    insurance DECIMAL(10,2) NOT NULL DEFAULT 0,
    maintenance_repairs DECIMAL(10,2) NOT NULL DEFAULT 0,
    management_fees DECIMAL(10,2) NOT NULL DEFAULT 0,
    utilities DECIMAL(10,2) NOT NULL DEFAULT 0,
    net_operating_income DECIMAL(10,2) GENERATED ALWAYS AS 
        (gross_rental_income - vacancy_loss + other_income - operating_expenses - property_taxes - insurance - maintenance_repairs - management_fees - utilities) STORED,
    occupancy_rate DECIMAL(5,4) NOT NULL DEFAULT 1.0000,
    FOREIGN KEY (property_id) REFERENCES properties(property_id),
    INDEX idx_property_period (property_id, period_start, period_end)
);

-- Leases table - Track tenant leases
CREATE TABLE leases (
    lease_id INT PRIMARY KEY AUTO_INCREMENT,
    property_id INT NOT NULL,
    tenant_name VARCHAR(200) NOT NULL,
    unit_number VARCHAR(50),
    lease_start_date DATE NOT NULL,
    lease_end_date DATE NOT NULL,
    monthly_rent DECIMAL(8,2) NOT NULL,
    security_deposit DECIMAL(8,2) NOT NULL DEFAULT 0,
    lease_type ENUM('Gross', 'Net', 'Modified Gross', 'Triple Net') NOT NULL DEFAULT 'Gross',
    square_footage INT,
    rent_per_sf DECIMAL(6,2) GENERATED ALWAYS AS (monthly_rent * 12 / NULLIF(square_footage, 0)) STORED,
    lease_status ENUM('Active', 'Expired', 'Terminated', 'Pending') NOT NULL DEFAULT 'Active',
    renewal_option BOOLEAN DEFAULT FALSE,
    escalation_rate DECIMAL(5,4) DEFAULT 0.0300,
    FOREIGN KEY (property_id) REFERENCES properties(property_id),
    INDEX idx_property_dates (property_id, lease_start_date, lease_end_date)
);

-- Market data - Track market metrics by area
CREATE TABLE market_data (
    market_id INT PRIMARY KEY AUTO_INCREMENT,
    market_name VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(2) NOT NULL,
    property_type ENUM('Office', 'Retail', 'Industrial', 'Multifamily', 'Hotel', 'Self Storage') NOT NULL,
    reporting_period DATE NOT NULL,
    average_cap_rate DECIMAL(5,4),
    average_rent_psf DECIMAL(6,2),
    vacancy_rate DECIMAL(5,4),
    absorption_sf INT,
    new_construction_sf INT,
    average_sale_price_psf DECIMAL(6,2),
    total_inventory_sf BIGINT,
    UNIQUE KEY unique_market_period (market_name, property_type, reporting_period),
    INDEX idx_market_type_period (market_name, property_type, reporting_period)
);

-- Transactions - Property sales and acquisitions
CREATE TABLE transactions (
    transaction_id INT PRIMARY KEY AUTO_INCREMENT,
    property_id INT NOT NULL,
    transaction_date DATE NOT NULL,
    transaction_type ENUM('Purchase', 'Sale', 'Refinance') NOT NULL,
    sale_price DECIMAL(12,2),
    price_per_sf DECIMAL(6,2),
    buyer_name VARCHAR(200),
    seller_name VARCHAR(200),
    financing_amount DECIMAL(12,2),
    down_payment DECIMAL(12,2),
    interest_rate DECIMAL(5,4),
    loan_term_months INT,
    cap_rate_at_sale DECIMAL(5,4),
    broker_commission DECIMAL(8,2),
    closing_costs DECIMAL(8,2),
    FOREIGN KEY (property_id) REFERENCES properties(property_id),
    INDEX idx_property_date (property_id, transaction_date)
);

-- Portfolio summary view
CREATE VIEW portfolio_summary AS
SELECT 
    p.property_type,
    COUNT(*) as property_count,
    SUM(p.square_footage) as total_sf,
    AVG(pv.appraised_value) as avg_property_value,
    SUM(pv.appraised_value) as total_portfolio_value,
    AVG(fp.net_operating_income * 12) as avg_annual_noi,
    AVG(fp.occupancy_rate) as avg_occupancy_rate,
    AVG(fp.net_operating_income * 12 / pv.appraised_value) as avg_cap_rate
FROM properties p
LEFT JOIN property_valuations pv ON p.property_id = pv.property_id 
    AND pv.valuation_date = (
        SELECT MAX(valuation_date) 
        FROM property_valuations pv2 
        WHERE pv2.property_id = p.property_id
    )
LEFT JOIN financial_performance fp ON p.property_id = fp.property_id
    AND fp.period_start = (
        SELECT MAX(period_start) 
        FROM financial_performance fp2 
        WHERE fp2.property_id = p.property_id
    )
GROUP BY p.property_type;

-- Lease expiration analysis view
CREATE VIEW lease_expiration_analysis AS
SELECT 
    p.property_id,
    p.address,
    p.property_type,
    COUNT(l.lease_id) as total_leases,
    SUM(l.monthly_rent) as total_monthly_rent,
    SUM(CASE WHEN l.lease_end_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 12 MONTH) 
             THEN l.monthly_rent ELSE 0 END) as expiring_rent_12mo,
    SUM(CASE WHEN l.lease_end_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 6 MONTH) 
             THEN l.monthly_rent ELSE 0 END) as expiring_rent_6mo,
    ROUND(SUM(CASE WHEN l.lease_end_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 12 MONTH) 
                   THEN l.monthly_rent ELSE 0 END) / SUM(l.monthly_rent) * 100, 2) as pct_expiring_12mo
FROM properties p
LEFT JOIN leases l ON p.property_id = l.property_id AND l.lease_status = 'Active'
GROUP BY p.property_id, p.address, p.property_type
HAVING total_leases > 0
ORDER BY pct_expiring_12mo DESC;

