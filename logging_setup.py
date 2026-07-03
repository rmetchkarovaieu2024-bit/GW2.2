"""Logging setup for export.py.

Every log line goes three places:
  - console (so you can watch a run happen)
  - logs/export.log (rotating file, local backup)
  - the log_events table in DATABASE_URL, via DBLogHandler (this is the part
    that matters: a queryable audit trail of everything that happened,
    not just the per-run summary in tracking.py's export_logs table)

Controlled via env vars (see .env.example):
    LOG_LEVEL   DEBUG|INFO|WARNING|ERROR  (default INFO)
    LOG_DIR     directory for the rotating log file (default ./logs)

Usage:
    from logging_setup import configure_logging, get_logger, ExportLogContext

    configure_logging()
    logger = get_logger(__name__)
    logger.info("plain message")

    with ExportLogContext(export_name="daily_transactions"):
        logger.info("this line is tagged with export_name automatically")
"""
import logging
import logging.handlers
import os
import sys
import threading

import tracking

# ── Thread-local context (safe for concurrent runs) ──────────────────────────
_ctx = threading.local()


def set_export_context(export_name: str):
    _ctx.export_name = export_name


def clear_export_context():
    _ctx.export_name = ""


def get_export_context() -> dict:
    return {"export_name": getattr(_ctx, "export_name", "")}


class ExportLogContext:
    """Context manager that sets and clears the thread-local export context.

    Usage:
        with ExportLogContext(export_name="daily_transactions"):
            logger.info("This log line will include export_name=daily_transactions")
    """

    def __init__(self, export_name: str):
        self.export_name = export_name

    def __enter__(self):
        set_export_context(self.export_name)
        return self

    def __exit__(self, *args):
        clear_export_context()


class ExportContextFilter(logging.Filter):
    """Injects the current export_name into every record."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.export_name = get_export_context()["export_name"] or "-"
        return True


class DBLogHandler(logging.Handler):
    """Writes every emitted record to the log_events table.

    If the database is unreachable, the failure is printed to stderr instead
    of raised (a logging call should never crash the export it's logging).
    """

    def emit(self, record: logging.LogRecord):
        try:
            tracking.log_event(
                level=record.levelname,
                logger=record.name,
                message=record.getMessage(),
                export_name=get_export_context()["export_name"],
            )
        except Exception as exc:
            print(f"[logging_setup] failed to write log_events row: {exc}", file=sys.stderr)


_FORMAT = "%(asctime)s [%(levelname)-8s] %(name)-20s | [%(export_name)s] %(message)s"

_configured = False


def configure_logging():
    """Call once at startup (export.py's main()). Safe to call more than once."""
    global _configured
    if _configured:
        return
    _configured = True

    level = getattr(logging, os.environ.get("LOG_LEVEL", "INFO").upper(), logging.INFO)
    log_dir = os.environ.get("LOG_DIR", "./logs")

    formatter = logging.Formatter(_FORMAT, "%Y-%m-%d %H:%M:%S")
    context_filter = ExportContextFilter()

    root = logging.getLogger()
    root.setLevel(level)
    for h in root.handlers[:]:
        root.removeHandler(h)

    console_h = logging.StreamHandler()
    console_h.setFormatter(formatter)
    console_h.addFilter(context_filter)
    root.addHandler(console_h)

    os.makedirs(log_dir, exist_ok=True)
    file_h = logging.handlers.RotatingFileHandler(
        os.path.join(log_dir, "export.log"),
        maxBytes=10 * 1024 * 1024,   # 10 MB
        backupCount=5,
        encoding="utf-8",
    )
    file_h.setFormatter(formatter)
    file_h.addFilter(context_filter)
    root.addHandler(file_h)

    db_h = DBLogHandler()
    db_h.setLevel(level)
    root.addHandler(db_h)

    # Quieten noisy third-party loggers
    logging.getLogger("paramiko").setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    """Return a logger. configure_logging() must have been called first."""
    return logging.getLogger(name)
