# export-lite

A stripped-down version of the export system: **CSV/Excel only, SFTP or email delivery,
on-demand only.** No scheduler, no queue, no plugin registry — just a CLI script with a
full audit trail of every run (ported from the tracking part of the
[GW repo](https://github.com/rmetchkarovaieu2024-bit/GW)).

## Setup

```bash
python3 -m venv venv && source venv/bin/activate
pip3 install -r requirements.txt
cp .env.example .env       # fill in DATABASE_URL, SFTP_*, and SMTP_* values
```

### Database

`.env.example` is pre-filled with the same example Postgres DB (name/user/password)
as the original GW repo: `export_db` / `export_user` / `export_pass`, published on
**host port 5433** (not 5432) so it doesn't collide with any other local Postgres
you might have running (e.g. a separate GW checkout). Spin up a local instance of
it, schema and all, with:

```bash
docker compose up -d
```

`scripts/init_db.sql` builds a ~50,000-row financial demo dataset across 8 tables:
`clients`, `accounts`, `transactions`, `gl_entries`, `positions`, `risk_metrics`,
`instruments`, `fx_rates`. A few bugs were fixed before wiring it in:
- `transactions` and `positions` generated `instrument_id` values 1-31 against an
  `instruments` table that only has 30 rows, so both inserts failed on a foreign
  key violation partway through. Fixed by generating 1-30 instead.
- `clients_csv`'s query (below) referenced a `created_at` column that doesn't
  exist on `clients` — the real column is `onboarded_date`. Fixed with an alias.
- `top_tier_client_feed`'s query referenced `c.email`, but the column is
  `contact_email`. Fixed.

All four exports in `definitions.yaml` were run against a live copy of this
dataset end-to-end (query -> DataFrame -> CSV/Excel file -> SFTP upload) and
confirmed to return real rows.

### SFTP

`docker compose up -d` also starts a local test SFTP server (`atmoz/sftp`) on
`localhost:2222`, pre-wired into `.env.example` (`sftp_user` / `sftp_pass`,
uploads land in `/incoming`). It's enough to exercise delivery end-to-end without
a real server. Uploaded files live inside the container only (not persisted to a
host volume — inspect with `docker exec export-lite-sftp ls /home/sftp_user/incoming`).
Point `SFTP_HOST`/`SFTP_PORT`/credentials at a real server when you're ready.

### Email

`docker compose up -d` also starts a local test SMTP server ([MailHog](https://github.com/mailhog/MailHog)),
pre-wired into `.env.example`. Exports with `delivery: email` are sent through it; nothing
is actually delivered externally — open http://localhost:8025 to see caught mail. Point
`SMTP_HOST`/`SMTP_PORT`/credentials at a real mail server when you're ready.

## Configure what to export

Edit `definitions.yaml`. Each entry needs:

```yaml
- name: my_export
  query: "SELECT * FROM my_table WHERE ..."
  format: csv        # or excel
  remote_filename: "my_export_{date}.csv"   # {date} -> YYYY-MM-DD
  delivery: sftp     # or "email" (defaults to sftp if omitted)
  email_to:          # required when delivery: email
    - someone@example.com
  zip: true          # or false to deliver the plain file uncompressed (defaults to true)
```

## Run

```bash
python3 export.py --list              # see available exports
python3 export.py --name my_export    # run one
python3 export.py --all               # run all of them
python3 export.py --name my_export --local-only   # write locally only, skip delivery
```

> On some systems (especially macOS), the `python` command may not be available by default. Use `python3` instead.

Each run: executes the query -> writes CSV/Excel to `LOCAL_OUTPUT_DIR` -> zips that file
(`<remote_filename>.zip`), unless the export sets `zip: false` -> delivers the result via
SFTP (upload to `SFTP_REMOTE_DIR`) or email (attachment via SMTP), per that export's
`delivery` setting -> logs progress -> records the outcome. `--local-only` skips the zip
step too, writing just the plain CSV/Excel file.

## Tracking & logging

Every run of `export.py`, whether it succeeds or fails, is recorded at two levels:

- **`export_logs`** — one row per run: `status` (`running`/`success`/`failed`),
  `started_at`/`completed_at`/`duration_ms`, `row_count`, `file_size_bytes`,
  `file_path`, `remote_path`, `error_message`.
- **`log_events`** — one row per individual log line emitted while that run
  happened (every `logger.info`/`.error`/... call: `running query...`, `got N rows`,
  `writing csv -> ...`, `uploading via SFTP -> ...`, and the error message + level
  on failure). This is the full play-by-play, not just the summary.

Both tables live in `DATABASE_URL`, written by `tracking.py`. `logging_setup.py` wires
a `DBLogHandler` into the standard `logging` module so every `logger.*()` call in the
app writes to `log_events` automatically — no need to call `tracking` directly outside
of `export.py`'s run/success/failure calls. Logs also go to the console and to
`logs/export.log` (rotating, `LOG_DIR`) as a local backup in case the database is down.
`LOG_LEVEL` (`DEBUG`/`INFO`/`WARNING`/`ERROR`) controls verbosity everywhere.

Query the audit trail directly, e.g.:

```sql
-- per-run summary
SELECT export_name, status, started_at, duration_ms, row_count, error_message
FROM export_logs
ORDER BY started_at DESC
LIMIT 20;

-- full play-by-play for one run
SELECT ts, level, message
FROM log_events
WHERE export_name = 'daily_transactions'
ORDER BY ts;
```

If your local Postgres volume was created before these tables existed, recreate it with
`docker compose down -v && docker compose up -d` (or run the `export_logs`/`log_events`
blocks from `scripts/init_db.sql` manually).

## Files

```
export.py                    CLI entrypoint
db.py                        runs the SQL query, returns a DataFrame
tracking.py                  records runs (export_logs) and log lines (log_events) to the DB
logging_setup.py             console + rotating file + DB logging (wires DBLogHandler into logging)
exporters/csv_exporter.py    DataFrame -> .csv
exporters/excel_exporter.py  DataFrame -> .xlsx
delivery/sftp_delivery.py    uploads a file over SFTP (password or key auth)
delivery/email_delivery.py   emails a file as an attachment via SMTP
definitions.yaml             what to export
scripts/init_db.sql          creates + seeds the example Postgres tables + export_logs/log_events
docker-compose.yml           spins up the example Postgres DB + local test SFTP + SMTP servers
.env.example                 DB + SFTP + SMTP + logging config template
```

## Notes

- `DATABASE_URL` is a standard SQLAlchemy URL, so Postgres/MySQL/SQLite all work —
  swap the driver package in `requirements.txt` if you're not on Postgres.
- SFTP auth uses a password OR a private key (`SFTP_PRIVATE_KEY_PATH`); key wins if both are set.
- There's no retry logic or scheduler here on purpose — add one later if you need it,
  but it wasn't in scope for "simpler."
