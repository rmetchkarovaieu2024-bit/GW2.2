-- ===========================================================================
-- MASSIVE FINANCIAL DATASET — Export System Demo
-- ~50,000 rows across 8 tables
-- Auto-run by docker-compose on first boot (mounted into
-- /docker-entrypoint-initdb.d). To re-run after editing, wipe the volume:
--   docker compose down -v && docker compose up -d
-- ===========================================================================

-- Clean up first (safe re-run)
DROP TABLE IF EXISTS log_events      CASCADE;
DROP TABLE IF EXISTS export_logs     CASCADE;
DROP TABLE IF EXISTS risk_metrics    CASCADE;
DROP TABLE IF EXISTS positions       CASCADE;
DROP TABLE IF EXISTS transactions    CASCADE;
DROP TABLE IF EXISTS gl_entries      CASCADE;
DROP TABLE IF EXISTS accounts        CASCADE;
DROP TABLE IF EXISTS clients         CASCADE;
DROP TABLE IF EXISTS instruments     CASCADE;
DROP TABLE IF EXISTS fx_rates        CASCADE;

-- ===========================================================================
-- TABLE 1: FX_RATES  (~500 rows)
-- ===========================================================================
CREATE TABLE fx_rates (
    id           SERIAL PRIMARY KEY,
    rate_date    DATE          NOT NULL,
    from_ccy     VARCHAR(3)    NOT NULL,
    to_ccy       VARCHAR(3)    NOT NULL DEFAULT 'USD',
    rate         NUMERIC(18,8) NOT NULL,
    source       VARCHAR(50)   DEFAULT 'ECB',
    UNIQUE(rate_date, from_ccy, to_ccy)
);

INSERT INTO fx_rates (rate_date, from_ccy, to_ccy, rate)
SELECT
    d::date,
    ccy,
    'USD',
    CASE ccy
        WHEN 'EUR' THEN ROUND((1.05 + SIN(EXTRACT(DOY FROM d) * 0.02) * 0.05 + RANDOM() * 0.02)::numeric, 8)
        WHEN 'GBP' THEN ROUND((1.25 + SIN(EXTRACT(DOY FROM d) * 0.015) * 0.06 + RANDOM() * 0.02)::numeric, 8)
        WHEN 'JPY' THEN ROUND((140  + SIN(EXTRACT(DOY FROM d) * 0.01) * 8    + RANDOM() * 2)::numeric, 8)
        WHEN 'CHF' THEN ROUND((1.10 + SIN(EXTRACT(DOY FROM d) * 0.018) * 0.04 + RANDOM() * 0.01)::numeric, 8)
        WHEN 'CAD' THEN ROUND((0.74 + SIN(EXTRACT(DOY FROM d) * 0.025) * 0.03 + RANDOM() * 0.01)::numeric, 8)
        WHEN 'AUD' THEN ROUND((0.65 + SIN(EXTRACT(DOY FROM d) * 0.02) * 0.04 + RANDOM() * 0.01)::numeric, 8)
    END
FROM
    generate_series(CURRENT_DATE - 730, CURRENT_DATE, '1 day') AS d,
    unnest(ARRAY['EUR','GBP','JPY','CHF','CAD','AUD']) AS ccy
WHERE EXTRACT(DOW FROM d) NOT IN (0, 6)
ON CONFLICT DO NOTHING;

-- ===========================================================================
-- TABLE 2: INSTRUMENTS  (~30 rows)
-- ===========================================================================
CREATE TABLE instruments (
    id             SERIAL PRIMARY KEY,
    isin           VARCHAR(12)  UNIQUE NOT NULL,
    ticker         VARCHAR(20),
    name           VARCHAR(255) NOT NULL,
    asset_class    VARCHAR(50),
    sub_class      VARCHAR(50),
    currency       VARCHAR(3),
    exchange       VARCHAR(50),
    sector         VARCHAR(100),
    country        VARCHAR(3),
    is_active      BOOLEAN DEFAULT TRUE
);

INSERT INTO instruments (isin, ticker, name, asset_class, sub_class, currency, exchange, sector, country) VALUES
('US0378331005','AAPL',  'Apple Inc',                    'Equity','Large Cap', 'USD','NASDAQ','Technology',       'US'),
('US5949181045','MSFT',  'Microsoft Corporation',        'Equity','Large Cap', 'USD','NASDAQ','Technology',       'US'),
('US02079K3059','GOOG',  'Alphabet Inc Class A',         'Equity','Large Cap', 'USD','NASDAQ','Technology',       'US'),
('US0231351067','AMZN',  'Amazon.com Inc',               'Equity','Large Cap', 'USD','NASDAQ','Consumer Disc',    'US'),
('US88160R1014','TSLA',  'Tesla Inc',                    'Equity','Large Cap', 'USD','NASDAQ','Consumer Disc',    'US'),
('US46625H1005','JPM',   'JPMorgan Chase & Co',          'Equity','Large Cap', 'USD','NYSE',  'Financials',       'US'),
('US38141G1040','GS',    'Goldman Sachs Group Inc',      'Equity','Large Cap', 'USD','NYSE',  'Financials',       'US'),
('US9311421039','WMT',   'Walmart Inc',                  'Equity','Large Cap', 'USD','NYSE',  'Consumer Staples', 'US'),
('US1667641005','CVX',   'Chevron Corporation',          'Equity','Large Cap', 'USD','NYSE',  'Energy',           'US'),
('US7170811035','PFE',   'Pfizer Inc',                   'Equity','Large Cap', 'USD','NYSE',  'Healthcare',       'US'),
('DE0005140008','DBK',   'Deutsche Bank AG',             'Equity','Large Cap', 'EUR','XETRA', 'Financials',       'DE'),
('DE0007164600','SAP',   'SAP SE',                       'Equity','Large Cap', 'EUR','XETRA', 'Technology',       'DE'),
('FR0000131104','BNP',   'BNP Paribas SA',               'Equity','Large Cap', 'EUR','EPA',   'Financials',       'FR'),
('GB0005405286','HSBA',  'HSBC Holdings plc',            'Equity','Large Cap', 'GBP','LSE',   'Financials',       'GB'),
('CH0012221716','ABB',   'ABB Ltd',                      'Equity','Large Cap', 'CHF','SIX',   'Industrials',      'CH'),
('US912796ZR05','UST2Y', 'US Treasury 2Y 4.50% 2026',   'Fixed Income','Government','USD','OTC','Government','US'),
('US912810TM79','UST10Y','US Treasury 10Y 3.875% 2033',  'Fixed Income','Government','USD','OTC','Government','US'),
('US912810TZ92','UST30Y','US Treasury 30Y 4.125% 2053',  'Fixed Income','Government','USD','OTC','Government','US'),
('DE0001102580','BUND5Y','German Bund 5Y 2.00% 2028',    'Fixed Income','Government','EUR','OTC','Government','DE'),
('DE0001135525','BUND10Y','German Bund 10Y 2.30% 2033',  'Fixed Income','Government','EUR','OTC','Government','DE'),
('GB00BN65R313','GILT10Y','UK Gilt 10Y 4.00% 2034',      'Fixed Income','Government','GBP','OTC','Government','GB'),
('XS2345678901','MS5Y',  'Morgan Stanley 5Y 4.75% 2029','Fixed Income','Corporate', 'USD','OTC','Financials','US'),
('XS2345678902','GS3Y',  'Goldman Sachs 3Y 5.00% 2027', 'Fixed Income','Corporate', 'USD','OTC','Financials','US'),
('US78462F1030','SPY',   'SPDR S&P 500 ETF Trust',      'ETF','Equity ETF',  'USD','NYSE','Broad Market','US'),
('US4642874576','IVV',   'iShares Core S&P 500 ETF',    'ETF','Equity ETF',  'USD','NYSE','Broad Market','US'),
('US9220427424','VTI',   'Vanguard Total Market ETF',   'ETF','Equity ETF',  'USD','NYSE','Broad Market','US'),
('IE00B4L5Y983','IWDA',  'iShares World ETF',           'ETF','Equity ETF',  'USD','LSE', 'Global',     'IE'),
('XC0009655157','XAUUSD','Gold Spot USD',               'Commodity','Precious Metal','USD','OTC','Commodity','--'),
('XC0009667715','XAGUSD','Silver Spot USD',             'Commodity','Precious Metal','USD','OTC','Commodity','--'),
('--0000000001','CRUDWTI','Crude Oil WTI Front Month',  'Commodity','Energy',       'USD','CME','Commodity','--');

-- ===========================================================================
-- TABLE 3: CLIENTS  (1,000 rows)
-- ===========================================================================
CREATE TABLE clients (
    id             SERIAL PRIMARY KEY,
    client_code    VARCHAR(20)  UNIQUE NOT NULL,
    company_name   VARCHAR(255) NOT NULL,
    legal_entity   VARCHAR(100),
    client_type    VARCHAR(50),
    contact_person VARCHAR(255),
    contact_email  VARCHAR(255),
    country        VARCHAR(3),
    city           VARCHAR(100),
    industry       VARCHAR(100),
    aum_usd        NUMERIC(18,2),
    credit_rating  VARCHAR(10),
    onboarded_date DATE,
    status         VARCHAR(20) DEFAULT 'active',
    gw_owner       VARCHAR(100),
    priority_tier  INT DEFAULT 2
);

INSERT INTO clients (
    client_code, company_name, legal_entity, client_type,
    contact_person, contact_email, country, city, industry,
    aum_usd, credit_rating, onboarded_date, status, gw_owner, priority_tier
)
SELECT
    'CLT-' || LPAD(n::text, 4, '0'),
    (ARRAY['Acme','Zenith','Atlas','Orion','Nexus','Apex','Vertex','Summit',
            'Pinnacle','Horizon','Sterling','Meridian','Cascade','Solaris','Polaris',
            'Aurora','Quantum','Helios','Titan','Phoenix','Olympus','Pegasus',
            'Neptune','Jupiter','Saturn','Vega','Sirius','Andromeda','Centaurus',
            'Rigel'])[1 + (n % 30)]
    || ' ' ||
    (ARRAY['Capital','Partners','Investments','Fund','Group','Holdings','Asset Management',
            'Securities','Wealth','Trust','Finance','Bank','Insurance','Pension','Global'])[1 + (n % 15)]
    || ' ' || n,
    (ARRAY['LLC','Ltd','AG','SA','NV','BV','GmbH','Plc','Corp','Inc'])[1 + (n % 10)],
    (ARRAY['Hedge Fund','Pension Fund','Insurance','Asset Manager','Private Bank',
            'Retail Bank','Investment Bank','Family Office','Sovereign Wealth',
            'Corporate Treasury'])[1 + (n % 10)],
    (ARRAY['Alice Johnson','Bob Smith','Carol White','David Brown','Emma Davis',
            'Frank Wilson','Grace Lee','Henry Martin','Iris Clark','James Taylor',
            'Karen Hughes','Liam Chen','Maria Santos','Noah Kim','Olivia Patel'])[1 + (n % 15)],
    'contact.' || n || '@client-' || n || '.com',
    (ARRAY['US','GB','DE','FR','NL','CH','BE','ES','IT','LU',
            'SG','HK','JP','AU','CA'])[1 + (n % 15)],
    (ARRAY['New York','London','Frankfurt','Paris','Amsterdam','Zurich','Brussels',
            'Madrid','Milan','Luxembourg','Singapore','Hong Kong','Tokyo','Sydney',
            'Toronto'])[1 + (n % 15)],
    (ARRAY['Banking','Insurance','Asset Management','Hedge Fund','Pension Fund',
            'Private Equity','Retail Banking','Corporate Finance','Investment Banking',
            'Fintech'])[1 + (n % 10)],
    ROUND((RANDOM() * 50000000000 + 100000000)::numeric, 2),
    (ARRAY['AAA','AA+','AA','AA-','A+','A','A-','BBB+','BBB','BBB-'])[1 + (n % 10)],
    CURRENT_DATE - (RANDOM() * 3650)::int,
    CASE WHEN n % 30 = 0 THEN 'inactive'
         WHEN n % 50 = 0 THEN 'under_review'
         ELSE 'active' END,
    (ARRAY['Sarah Connor','John Wick','Ellen Ripley','Tony Stark','Bruce Wayne',
            'Diana Prince','Peter Parker','Clark Kent','Natasha Romanoff','Steve Rogers'])[1 + (n % 10)],
    CASE WHEN n % 10 = 0 THEN 1 WHEN n % 4 = 0 THEN 2 ELSE 3 END
FROM generate_series(1, 1000) AS n;

-- ===========================================================================
-- TABLE 4: ACCOUNTS  (3,000 rows)
-- ===========================================================================
CREATE TABLE accounts (
    id              SERIAL PRIMARY KEY,
    account_number  VARCHAR(20)  UNIQUE NOT NULL,
    client_id       INT          REFERENCES clients(id),
    account_type    VARCHAR(50),
    currency        VARCHAR(3),
    balance         NUMERIC(18,2) DEFAULT 0,
    nav             NUMERIC(18,2) DEFAULT 0,
    credit_limit    NUMERIC(18,2) DEFAULT 0,
    opened_date     DATE,
    last_activity   TIMESTAMP,
    custodian       VARCHAR(100),
    prime_broker    VARCHAR(100),
    status          VARCHAR(20)  DEFAULT 'active',
    is_internal     BOOLEAN      DEFAULT FALSE
);

INSERT INTO accounts (
    account_number, client_id, account_type, currency,
    balance, nav, credit_limit, opened_date, last_activity,
    custodian, prime_broker, status, is_internal
)
SELECT
    'ACC-' || LPAD(n::text, 6, '0'),
    1 + (n % 1000),
    (ARRAY['Custody','Trading','Cash Management','Derivatives','Repo','Securities Lending',
            'FX','Margin','Prime Brokerage','Investment'])[1 + (n % 10)],
    (ARRAY['USD','EUR','GBP','CHF','JPY','CAD','AUD','USD','EUR','USD'])[1 + (n % 10)],
    ROUND((RANDOM() * 100000000 + 10000)::numeric, 2),
    ROUND((RANDOM() * 150000000 + 10000)::numeric, 2),
    ROUND((RANDOM() * 50000000)::numeric, 2),
    CURRENT_DATE - (RANDOM() * 3000)::int,
    NOW() - ((RANDOM() * 30)::int || ' days')::interval,
    (ARRAY['BNY Mellon','State Street','Citi','JPMorgan','Deutsche Bank',
            'HSBC','Euroclear','Clearstream','SIX','DTCC'])[1 + (n % 10)],
    (ARRAY['Goldman Sachs','Morgan Stanley','JPMorgan','Credit Suisse','Deutsche Bank',
            'UBS','Barclays','BNP Paribas','Societe Generale','HSBC'])[1 + (n % 10)],
    CASE WHEN n % 40 = 0 THEN 'frozen'
         WHEN n % 80 = 0 THEN 'closed'
         WHEN n % 100 = 0 THEN 'suspended'
         ELSE 'active' END,
    n % 50 = 0
FROM generate_series(1, 3000) AS n;

-- ===========================================================================
-- TABLE 5: TRANSACTIONS  (20,000 rows)
-- ===========================================================================
CREATE TABLE transactions (
    id              SERIAL PRIMARY KEY,
    txn_reference   VARCHAR(40)  UNIQUE NOT NULL,
    account_id      INT          REFERENCES accounts(id),
    instrument_id   INT          REFERENCES instruments(id),
    txn_type        VARCHAR(50),
    direction       VARCHAR(10),
    quantity        NUMERIC(18,4),
    price           NUMERIC(18,6),
    gross_amount    NUMERIC(18,2),
    net_amount      NUMERIC(18,2),
    commission      NUMERIC(18,2) DEFAULT 0,
    tax             NUMERIC(18,2) DEFAULT 0,
    currency        VARCHAR(3),
    fx_rate         NUMERIC(18,8) DEFAULT 1,
    status          VARCHAR(20),
    trade_date      DATE,
    value_date      DATE,
    settlement_date DATE,
    counterparty    VARCHAR(255),
    trader          VARCHAR(100),
    desk            VARCHAR(100),
    strategy        VARCHAR(100),
    notes           TEXT,
    created_at      TIMESTAMP    DEFAULT NOW()
);

INSERT INTO transactions (
    txn_reference, account_id, instrument_id, txn_type, direction,
    quantity, price, gross_amount, net_amount, commission, tax,
    currency, fx_rate, status,
    trade_date, value_date, settlement_date,
    counterparty, trader, desk, strategy, created_at
)
SELECT
    'TXN-' || TO_CHAR(NOW() - ((n % 730) || ' days')::interval, 'YYYYMMDD')
           || '-' || LPAD(n::text, 6, '0'),
    1 + (n % 3000),
    1 + (n % 30),
    (ARRAY['Trade','Transfer','Dividend','Corporate Action','Fee','Coupon',
            'Redemption','Subscription','FX Deal','Repo Open','Repo Close',
            'Stock Borrow','Stock Lend','Margin Call','Settlement'])[1 + (n % 15)],
    (ARRAY['BUY','SELL','BUY','SELL','IN','OUT','BUY','SELL','BUY','SELL'])[1 + (n % 10)],
    ROUND((RANDOM() * 100000 + 100)::numeric, 4),
    ROUND((RANDOM() * 1000 + 1)::numeric, 6),
    ROUND((RANDOM() * 5000000 + 1000)::numeric, 2),
    ROUND((RANDOM() * 4990000 + 1000)::numeric, 2),
    ROUND((RANDOM() * 5000)::numeric, 2),
    ROUND((RANDOM() * 2000)::numeric, 2),
    (ARRAY['USD','EUR','GBP','CHF','JPY','CAD','USD','USD','EUR','GBP'])[1 + (n % 10)],
    ROUND((0.85 + RANDOM() * 0.30)::numeric, 8),
    (ARRAY['settled','settled','settled','settled','pending','processing',
            'failed','cancelled','partially_settled','on_hold'])[1 + (n % 10)],
    (NOW() - ((n % 730) || ' days')::interval)::date,
    (NOW() - ((n % 730 - 2) || ' days')::interval)::date,
    (NOW() - ((n % 730 - 3) || ' days')::interval)::date,
    (ARRAY['Goldman Sachs','Morgan Stanley','JP Morgan','Deutsche Bank','BNP Paribas',
            'UBS','Credit Suisse','Barclays','HSBC','Citibank',
            'Societe Generale','Nomura','Merrill Lynch','Jefferies','Piper Sandler'])[1 + (n % 15)],
    (ARRAY['T.Smith','A.Johnson','B.Chen','C.Patel','D.Kumar',
            'E.Wilson','F.Brown','G.Taylor','H.Martin','I.Davis'])[1 + (n % 10)],
    (ARRAY['Equities EU','Equities US','Fixed Income','FX','Derivatives',
            'Commodities','Emerging Markets','Prime Services','Rates','Credit'])[1 + (n % 10)],
    (ARRAY['Long/Short','Market Neutral','Global Macro','Event Driven','Arbitrage',
            'Quantitative','Index Tracking','Momentum','Value','Growth'])[1 + (n % 10)],
    NOW() - ((n % 730) || ' days')::interval
FROM generate_series(1, 20000) AS n;

-- ===========================================================================
-- TABLE 6: GL_ENTRIES  (10,000 rows)
-- ===========================================================================
CREATE TABLE gl_entries (
    id              SERIAL PRIMARY KEY,
    entry_ref       VARCHAR(40)  UNIQUE NOT NULL,
    journal_id      VARCHAR(20),
    gl_account      VARCHAR(20)  NOT NULL,
    gl_description  VARCHAR(255),
    debit_amount    NUMERIC(18,2) DEFAULT 0,
    credit_amount   NUMERIC(18,2) DEFAULT 0,
    currency        VARCHAR(3),
    base_debit      NUMERIC(18,2) DEFAULT 0,
    base_credit     NUMERIC(18,2) DEFAULT 0,
    posting_date    DATE,
    period          VARCHAR(7),
    fiscal_year     INT,
    quarter         INT,
    department      VARCHAR(100),
    cost_centre     VARCHAR(50),
    entity          VARCHAR(100),
    status          VARCHAR(20)  DEFAULT 'posted',
    approved_by     VARCHAR(100),
    created_at      TIMESTAMP    DEFAULT NOW()
);

INSERT INTO gl_entries (
    entry_ref, journal_id, gl_account, gl_description,
    debit_amount, credit_amount, currency, base_debit, base_credit,
    posting_date, period, fiscal_year, quarter,
    department, cost_centre, entity, status, approved_by, created_at
)
SELECT
    'GL-' || TO_CHAR(CURRENT_DATE - (n % 730), 'YYYYMMDD') || '-' || LPAD(n::text, 6, '0'),
    'JNL-' || LPAD((n / 5)::text, 5, '0'),
    (ARRAY['1000','1010','1020','1100','1110','1200','1210','1300',
            '2000','2010','2100','2200','3000','3100',
            '4000','4100','4200','4300','4400',
            '5000','5100','5200','5300','5400','5500',
            '6000','6100','6200','7000','8000'])[1 + (n % 30)],
    (ARRAY['Cash - Operational','Cash - Client','Cash - Collateral',
            'Receivables - Fees','Receivables - Trades','Investments - Listed',
            'Investments - OTC','Prepaid Expenses',
            'Payables - Trades','Payables - Expenses','Accrued Liabilities',
            'Client Deposits',
            'Share Capital','Retained Earnings',
            'Revenue - Management Fees','Revenue - Performance Fees',
            'Revenue - Trading','Revenue - FX','Revenue - Interest',
            'Salaries & Benefits','Technology & Systems','Compliance & Legal',
            'Risk Management','Operations','Research',
            'Office & Facilities','Travel & Entertainment',
            'Depreciation','Tax Provision','Interest Expense'])[1 + (n % 30)],
    CASE WHEN n % 2 = 0 THEN ROUND((RANDOM() * 2000000 + 1000)::numeric, 2) ELSE 0 END,
    CASE WHEN n % 2 = 1 THEN ROUND((RANDOM() * 2000000 + 1000)::numeric, 2) ELSE 0 END,
    (ARRAY['USD','EUR','GBP','CHF','USD','EUR','USD','USD','EUR','GBP'])[1 + (n % 10)],
    CASE WHEN n % 2 = 0 THEN ROUND((RANDOM() * 2200000 + 1000)::numeric, 2) ELSE 0 END,
    CASE WHEN n % 2 = 1 THEN ROUND((RANDOM() * 2200000 + 1000)::numeric, 2) ELSE 0 END,
    CURRENT_DATE - (n % 730),
    TO_CHAR(CURRENT_DATE - (n % 730), 'YYYY-MM'),
    EXTRACT(YEAR FROM CURRENT_DATE - (n % 730))::int,
    EXTRACT(QUARTER FROM CURRENT_DATE - (n % 730))::int,
    (ARRAY['Finance','Operations','Technology','Compliance','Front Office',
            'Risk Management','Human Resources','Legal','Marketing',
            'Settlements','Client Services','Executive'])[1 + (n % 12)],
    'CC-' || LPAD((1 + n % 20)::text, 3, '0'),
    (ARRAY['GW Capital Ltd','GW Securities Inc','GW Asset Management',
            'GW Holdings AG','GW Investments NV'])[1 + (n % 5)],
    CASE WHEN n % 50 = 0 THEN 'reversed'
         WHEN n % 100 = 0 THEN 'pending'
         ELSE 'posted' END,
    (ARRAY['J.Finance','K.Accounts','L.Controller','M.CFO','N.Auditor'])[1 + (n % 5)],
    NOW() - ((n % 730) || ' days')::interval
FROM generate_series(1, 10000) AS n;

-- ===========================================================================
-- TABLE 7: POSITIONS  (8,000 rows)
-- ===========================================================================
CREATE TABLE positions (
    id              SERIAL PRIMARY KEY,
    account_id      INT           REFERENCES accounts(id),
    instrument_id   INT           REFERENCES instruments(id),
    quantity        NUMERIC(18,4) DEFAULT 0,
    avg_cost        NUMERIC(18,6),
    market_price    NUMERIC(18,6),
    market_value    NUMERIC(18,2),
    cost_basis      NUMERIC(18,2),
    unrealised_pnl  NUMERIC(18,2),
    realised_pnl    NUMERIC(18,2) DEFAULT 0,
    accrued_income  NUMERIC(18,2) DEFAULT 0,
    currency        VARCHAR(3),
    position_date   DATE,
    dirty_price     NUMERIC(18,6),
    duration        NUMERIC(8,4),
    modified_duration NUMERIC(8,4),
    created_at      TIMESTAMP     DEFAULT NOW(),
    UNIQUE(account_id, instrument_id, position_date)
);

INSERT INTO positions (
    account_id, instrument_id, quantity, avg_cost, market_price,
    market_value, cost_basis, unrealised_pnl, realised_pnl, accrued_income,
    currency, position_date, dirty_price, duration, modified_duration
)
SELECT
    1 + (n % 3000),
    1 + (n % 30),
    ROUND((RANDOM() * 500000 + 100)::numeric, 4),
    ROUND((RANDOM() * 800 + 10)::numeric,  6),
    ROUND((RANDOM() * 800 + 10)::numeric,  6),
    ROUND((RANDOM() * 50000000 + 1000)::numeric, 2),
    ROUND((RANDOM() * 45000000 + 1000)::numeric, 2),
    ROUND((RANDOM() * 4000000 - 2000000)::numeric, 2),
    ROUND((RANDOM() * 2000000 - 500000)::numeric,  2),
    ROUND((RANDOM() * 50000)::numeric, 2),
    (ARRAY['USD','EUR','GBP','CHF','JPY','CAD','USD','USD','EUR','GBP'])[1 + (n % 10)],
    CURRENT_DATE,
    ROUND((RANDOM() * 810 + 10)::numeric, 6),
    CASE WHEN n % 3 = 0 THEN ROUND((RANDOM() * 10 + 0.5)::numeric, 4) ELSE NULL END,
    CASE WHEN n % 3 = 0 THEN ROUND((RANDOM() * 9  + 0.4)::numeric, 4) ELSE NULL END
FROM generate_series(1, 8000) AS n
ON CONFLICT DO NOTHING;

-- ===========================================================================
-- TABLE 8: RISK_METRICS  (6,000 rows)
-- ===========================================================================
CREATE TABLE risk_metrics (
    id                  SERIAL PRIMARY KEY,
    account_id          INT          REFERENCES accounts(id),
    metric_date         DATE,
    var_1d_95           NUMERIC(18,2),
    var_1d_99           NUMERIC(18,2),
    var_10d_99          NUMERIC(18,2),
    expected_shortfall  NUMERIC(18,2),
    gross_exposure      NUMERIC(18,2),
    net_exposure        NUMERIC(18,2),
    long_exposure       NUMERIC(18,2),
    short_exposure      NUMERIC(18,2),
    leverage            NUMERIC(8,4),
    delta               NUMERIC(18,6),
    gamma               NUMERIC(18,6),
    vega                NUMERIC(18,6),
    theta               NUMERIC(18,6),
    beta                NUMERIC(8,4),
    correlation_spy     NUMERIC(8,4),
    sharpe_ratio        NUMERIC(8,4),
    sortino_ratio       NUMERIC(8,4),
    max_drawdown        NUMERIC(8,4),
    volatility_ann      NUMERIC(8,4),
    currency            VARCHAR(3),
    model_version       VARCHAR(20)  DEFAULT 'RiskEngine-v3',
    created_at          TIMESTAMP    DEFAULT NOW(),
    UNIQUE(account_id, metric_date)
);

INSERT INTO risk_metrics (
    account_id, metric_date,
    var_1d_95, var_1d_99, var_10d_99, expected_shortfall,
    gross_exposure, net_exposure, long_exposure, short_exposure, leverage,
    delta, gamma, vega, theta,
    beta, correlation_spy, sharpe_ratio, sortino_ratio, max_drawdown, volatility_ann,
    currency, model_version
)
SELECT
    1 + (n % 3000),
    CURRENT_DATE - (n % 60),
    ROUND((RANDOM() * 800000  + 5000)::numeric,  2),
    ROUND((RANDOM() * 1200000 + 8000)::numeric,  2),
    ROUND((RANDOM() * 3800000 + 25000)::numeric, 2),
    ROUND((RANDOM() * 1500000 + 10000)::numeric, 2),
    ROUND((RANDOM() * 100000000 + 500000)::numeric, 2),
    ROUND((RANDOM() * 50000000  - 25000000)::numeric, 2),
    ROUND((RANDOM() * 75000000  + 500000)::numeric, 2),
    ROUND((RANDOM() * 25000000)::numeric, 2),
    ROUND((RANDOM() * 8 + 0.5)::numeric, 4),
    ROUND((RANDOM() * 2  - 1)::numeric,  6),
    ROUND((RANDOM() * 0.1)::numeric,     6),
    ROUND((RANDOM() * 5000)::numeric,    6),
    ROUND((RANDOM() * -500)::numeric,    6),
    ROUND((RANDOM() * 2.5 - 0.5)::numeric, 4),
    ROUND((RANDOM() * 2   - 1)::numeric,    4),
    ROUND((RANDOM() * 4   - 1)::numeric,    4),
    ROUND((RANDOM() * 5   - 1)::numeric,    4),
    ROUND((RANDOM() * 0.6)::numeric,        4),
    ROUND((RANDOM() * 0.5 + 0.05)::numeric, 4),
    (ARRAY['USD','EUR','GBP','CHF','USD','EUR','USD','USD'])[1 + (n % 8)],
    (ARRAY['RiskEngine-v3','RiskEngine-v3','RiskEngine-v3','RiskEngine-v2'])[1 + (n % 4)]
FROM generate_series(1, 6000) AS n
ON CONFLICT DO NOTHING;

-- ===========================================================================
-- INDEXES for fast export queries
-- ===========================================================================
CREATE INDEX IF NOT EXISTS idx_txn_account     ON transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_txn_trade_date  ON transactions(trade_date);
CREATE INDEX IF NOT EXISTS idx_txn_status      ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_txn_created     ON transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gl_posting_date ON gl_entries(posting_date);
CREATE INDEX IF NOT EXISTS idx_gl_period       ON gl_entries(period);
CREATE INDEX IF NOT EXISTS idx_gl_department   ON gl_entries(department);
CREATE INDEX IF NOT EXISTS idx_pos_date        ON positions(position_date);
CREATE INDEX IF NOT EXISTS idx_risk_date       ON risk_metrics(metric_date);
CREATE INDEX IF NOT EXISTS idx_acc_client      ON accounts(client_id);
CREATE INDEX IF NOT EXISTS idx_acc_status      ON accounts(status);

-- ===========================================================================
-- EXPORT_LOGS — audit trail of every export.py run (ported from the tracking
-- part of the GW repo: https://github.com/rmetchkarovaieu2024-bit/GW)
-- ===========================================================================
CREATE TABLE export_logs (
    id                SERIAL PRIMARY KEY,
    export_name       VARCHAR(255) NOT NULL,
    triggered_by      VARCHAR(50)  NOT NULL DEFAULT 'manual',   -- manual|cli
    status            VARCHAR(50)  NOT NULL DEFAULT 'running',  -- running|success|failed
    started_at        TIMESTAMP    NOT NULL DEFAULT NOW(),
    completed_at      TIMESTAMP,
    duration_ms       INT,
    row_count         INT,
    file_size_bytes   BIGINT,
    file_path         VARCHAR(500),
    remote_path       VARCHAR(500),
    error_message     TEXT,
    created_at        TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_export_logs_name       ON export_logs(export_name);
CREATE INDEX IF NOT EXISTS idx_export_logs_status     ON export_logs(status);
CREATE INDEX IF NOT EXISTS idx_export_logs_started_at ON export_logs(started_at DESC);

-- ===========================================================================
-- LOG_EVENTS — every log line emitted while export.py runs (one row per
-- logger.info/warning/error/... call), not just the per-run summary above.
-- ===========================================================================
CREATE TABLE log_events (
    id            SERIAL PRIMARY KEY,
    ts            TIMESTAMP    NOT NULL DEFAULT NOW(),
    level         VARCHAR(20)  NOT NULL,
    logger        VARCHAR(255),
    export_name   VARCHAR(255),
    message       TEXT         NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_log_events_export_name ON log_events(export_name);
CREATE INDEX IF NOT EXISTS idx_log_events_ts           ON log_events(ts DESC);
CREATE INDEX IF NOT EXISTS idx_log_events_level        ON log_events(level);
