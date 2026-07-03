"""Records everything that happens during an export run to the database:
one summary row per run in export_logs, and one row per log line in log_events.

Ported (trimmed down) from the tracking part of the GW repo:
https://github.com/rmetchkarovaieu2024-bit/GW (models/export_log.py + schema.sql)

Usage:
    run = tracking.start_run("daily_transactions")
    try:
        ...
        tracking.mark_success(run, row_count=123, file_path=local_path, remote_path=remote_path)
    except Exception as exc:
        tracking.mark_failed(run, str(exc))
        raise
"""
import os
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import (
    BigInteger, Column, DateTime, Integer, MetaData, String, Table, Text,
    create_engine, insert, update,
)

_engine = None
_metadata = None
_export_logs = None
_log_events = None


def _init():
    global _engine, _metadata, _export_logs, _log_events
    if _engine is not None:
        return
    _engine = create_engine(os.environ["DATABASE_URL"])
    _metadata = MetaData()
    _export_logs = Table(
        "export_logs", _metadata,
        Column("id", Integer, primary_key=True),
        Column("export_name", String(255)),
        Column("triggered_by", String(50)),
        Column("status", String(50)),
        Column("started_at", DateTime),
        Column("completed_at", DateTime),
        Column("duration_ms", Integer),
        Column("row_count", Integer),
        Column("file_size_bytes", BigInteger),
        Column("file_path", String(500)),
        Column("remote_path", String(500)),
        Column("error_message", Text),
    )
    _log_events = Table(
        "log_events", _metadata,
        Column("id", Integer, primary_key=True),
        Column("ts", DateTime),
        Column("level", String(20)),
        Column("logger", String(255)),
        Column("export_name", String(255)),
        Column("message", Text),
    )


def start_run(export_name: str, triggered_by: str = "manual") -> dict:
    """Insert a 'running' row for this export and return a handle to it."""
    _init()
    started_at = datetime.now(timezone.utc)
    with _engine.begin() as conn:
        result = conn.execute(
            insert(_export_logs).values(
                export_name=export_name,
                triggered_by=triggered_by,
                status="running",
                started_at=started_at,
            )
        )
        log_id = result.inserted_primary_key[0]
    return {"id": log_id, "started_at": started_at}


def mark_success(run: dict, row_count: int, file_path: str, remote_path: Optional[str] = None):
    _init()
    completed_at = datetime.now(timezone.utc)
    file_size = os.path.getsize(file_path) if os.path.exists(file_path) else None
    with _engine.begin() as conn:
        conn.execute(
            update(_export_logs).where(_export_logs.c.id == run["id"]).values(
                status="success",
                completed_at=completed_at,
                duration_ms=int((completed_at - run["started_at"]).total_seconds() * 1000),
                row_count=row_count,
                file_size_bytes=file_size,
                file_path=file_path,
                remote_path=remote_path,
            )
        )


def mark_failed(run: dict, error_message: str):
    _init()
    completed_at = datetime.now(timezone.utc)
    with _engine.begin() as conn:
        conn.execute(
            update(_export_logs).where(_export_logs.c.id == run["id"]).values(
                status="failed",
                completed_at=completed_at,
                duration_ms=int((completed_at - run["started_at"]).total_seconds() * 1000),
                error_message=error_message[:2000],
            )
        )


def log_event(level: str, logger: str, message: str, export_name: str = ""):
    """Write a single log line to the log_events table. Called by
    logging_setup.DBLogHandler for every log record emitted by the app."""
    _init()
    with _engine.begin() as conn:
        conn.execute(
            insert(_log_events).values(
                ts=datetime.now(timezone.utc),
                level=level,
                logger=logger,
                export_name=export_name or None,
                message=message[:4000],
            )
        )
