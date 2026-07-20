-- ===========================================================================
-- EXPORT_DEFINITIONS — replaces definitions.yaml. export.py reads its list
-- of exports from this table instead of a file, via definitions_repo.py.
--
-- Kept in its own file (separate from init_db.sql, which owns the financial
-- demo dataset) so that re-running/reseeding one never drops or recreates
-- the other. Auto-run by docker-compose on first boot (mounted into
-- /docker-entrypoint-initdb.d, alongside init_db.sql). To re-apply by hand:
--   docker exec -i export-lite-postgres psql -U export_user -d export_db \
--     < scripts/init_definitions.sql
-- ===========================================================================
DROP TABLE IF EXISTS export_definitions CASCADE;

CREATE TABLE export_definitions (
    id              SERIAL PRIMARY KEY,
    name            VARCHAR(255) UNIQUE NOT NULL,
    description     TEXT,
    query           TEXT         NOT NULL,
    format          VARCHAR(20)  NOT NULL,               -- csv|excel
    remote_filename VARCHAR(255) NOT NULL,                -- supports a {date} placeholder
    delivery        VARCHAR(20)  NOT NULL DEFAULT 'sftp', -- sftp|email
    email_to        JSONB,                                -- array of addresses; null unless delivery='email'
    zip             BOOLEAN      NOT NULL DEFAULT FALSE,
    format_config   JSONB,                                -- e.g. {"delimiter": "|"} or {"sheet_name": "..."}
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_export_definitions_active ON export_definitions(is_active);

INSERT INTO export_definitions
    (name, description, query, format, remote_filename, delivery, email_to, zip, format_config)
VALUES
(
    'daily_transactions',
    'Trades executed today, one row per transaction, delivered to SFTP.',
    $q$SELECT
        t.txn_reference,
        t.trade_date,
        c.company_name AS client_name,
        t.direction,
        t.quantity,
        t.gross_amount,
        t.currency,
        t.status
    FROM transactions t
    JOIN accounts a ON a.id = t.account_id
    JOIN clients  c ON c.id = a.client_id
    WHERE t.trade_date >= CURRENT_DATE - INTERVAL '1 day'
    ORDER BY t.trade_date DESC$q$,
    'csv', 'daily_transactions_{date}.csv', 'sftp', NULL, FALSE, NULL
),
(
    'weekly_revenue_report',
    'Weekly revenue by GL line (accounts starting ''4''), Excel, delivered to SFTP.',
    $q$SELECT
        gl_description AS revenue_line,
        COUNT(*)          AS entries,
        SUM(credit_amount) AS revenue
    FROM gl_entries
    WHERE posting_date >= CURRENT_DATE - INTERVAL '7 days'
      AND gl_account LIKE '4%'
    GROUP BY gl_description
    ORDER BY revenue DESC$q$,
    'excel', 'weekly_revenue_report_{date}.xlsx', 'sftp', NULL, FALSE, NULL
),
(
    'top_tier_client_feed',
    'Active clients with the highest total account balance, delivered to partner SFTP.',
    $q$SELECT
        c.client_code,
        c.company_name,
        c.contact_person,
        c.contact_email,
        c.country,
        SUM(a.balance) AS total_balance
    FROM clients c
    JOIN accounts a ON a.client_id = c.id
    WHERE c.status = 'active'
    GROUP BY c.client_code, c.company_name, c.contact_person, c.contact_email, c.country
    ORDER BY total_balance DESC$q$,
    'csv', 'top_tier_client_feed_{date}.csv', 'sftp', NULL, FALSE, NULL
),
(
    'clients_csv',
    'Full client list, delivered to SFTP.',
    $q$SELECT
        client_code,
        company_name,
        country,
        industry,
        status,
        onboarded_date AS created_at
    FROM clients
    ORDER BY onboarded_date DESC$q$,
    'csv', 'clients_{date}.csv', 'sftp', NULL, FALSE, NULL
),
(
    'clients_email_digest',
    'Full client list, emailed as a CSV attachment to the ops distribution list.',
    $q$SELECT
        client_code,
        company_name,
        country,
        industry,
        status,
        onboarded_date AS created_at
    FROM clients
    ORDER BY onboarded_date DESC$q$,
    'csv', 'clients_digest_{date}.csv', 'email', '["raya.metche@gmail.com"]'::jsonb, FALSE, NULL
),
(
    'top_tier_client_feed_raw',
    'Same as top_tier_client_feed, but the partner''s ingestion job expects a plain CSV, not a zip.',
    $q$SELECT
        c.client_code,
        c.company_name,
        c.contact_person,
        c.contact_email,
        c.country,
        SUM(a.balance) AS total_balance
    FROM clients c
    JOIN accounts a ON a.client_id = c.id
    WHERE c.status = 'active'
    GROUP BY c.client_code, c.company_name, c.contact_person, c.contact_email, c.country
    ORDER BY total_balance DESC$q$,
    'csv', 'top_tier_client_feed_raw_{date}.csv', 'email', '["raya.metche@gmail.com"]'::jsonb, TRUE, NULL
);
