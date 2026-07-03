# export-lite

A stripped-down version of the export system: **CSV/Excel only, SFTP only, on-demand only.**
No scheduler, no queue, no plugin registry — just a CLI script with a full audit trail of
every run (ported from the tracking part of the
[GW repo](https://github.com/rmetchkarovaieu2024-bit/GW)).

## Setup

```bash
python3 -m venv venv && source venv/bin/activate
pip3 install -r requirements.txt
cp .env.example .env       # fill in DATABASE_URL and SFTP_* values
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

## Configure what to export

Edit `definitions.yaml`. Each entry needs:

```yaml
- name: my_export
  query: "SELECT * FROM my_table WHERE ..."
  format: csv        # or excel
  remote_filename: "my_export_{date}.csv"   # {date} -> YYYY-MM-DD
```

## Run

```bash
python3 export.py --list              # see available exports
python3 export.py --name my_export    # run one
python3 export.py --all               # run all of them
python3 export.py --name my_export --local-only   # write locally only, skip SFTP upload
```

> On some systems (especially macOS), the `python` command may not be available by default. Use `python3` instead.

Each run: executes the query -> writes CSV/Excel to `LOCAL_OUTPUT_DIR` -> uploads it to
`SFTP_REMOTE_DIR` on the configured SFTP server -> logs progress -> records the outcome.

## Tracking & logging

Every run of `export.py`, whether it succeeds or fails, is logged in two places:

- **Console + rotating file** (`logs/export.log` by default) via `logging_setup.py`.
  Controlled with `LOG_LEVEL` (`DEBUG`/`INFO`/`WARNING`/`ERROR`), `LOG_FORMAT`
  (`text` for humans, `json` for shipping to ELK/Loki), and `LOG_DIR`.
- **`export_logs` table** in `DATABASE_URL` via `tracking.py` — one row per run with
  `status` (`running`/`success`/`failed`), `started_at`/`completed_at`/`duration_ms`,
  `row_count`, `file_size_bytes`, `file_path`, `remote_path`, and `error_message` on failure.
  This is the same audit-trail shape as the `export_logs` table in the original GW repo,
  trimmed down (no `export_id`/`schedule_id` foreign keys, since export-lite's exports
  live in `definitions.yaml` rather than a database table).

Query it directly, e.g.:

```sql
SELECT export_name, status, started_at, duration_ms, row_count, error_message
FROM export_logs
ORDER BY started_at DESC
LIMIT 20;
```

If your local Postgres volume was created before this table existed, recreate it with
`docker compose down -v && docker compose up -d` (or run the `export_logs` block from
`scripts/init_db.sql` manually).

## Files

```
export.py                    CLI entrypoint
db.py                        runs the SQL query, returns a DataFrame
tracking.py                  records each run to the export_logs table
logging_setup.py             console + rotating file logging
exporters/csv_exporter.py    DataFrame -> .csv
exporters/excel_exporter.py  DataFrame -> .xlsx
delivery/sftp_delivery.py    uploads a file over SFTP (password or key auth)
definitions.yaml             what to export
scripts/init_db.sql          creates + seeds the example Postgres tables + export_logs
docker-compose.yml           spins up the example Postgres DB + a local test SFTP server
.env.example                 DB + SFTP + logging config template
```

## Notes

- `DATABASE_URL` is a standard SQLAlchemy URL, so Postgres/MySQL/SQLite all work —
  swap the driver package in `requirements.txt` if you're not on Postgres.
- SFTP auth uses a password OR a private key (`SFTP_PRIVATE_KEY_PATH`); key wins if both are set.
- There's no retry logic or scheduler here on purpose — add one later if you need it,
  but it wasn't in scope for "simpler."
