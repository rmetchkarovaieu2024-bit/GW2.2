"""Structured console + rotating file logging for export.py.

Ported (trimmed down) from the tracking part of the GW repo:
https://github.com/rmetchkarovaieu2024-bit/GW (core/logger.py)

Controlled via env vars (see .env.example):
    LOG_LEVEL   DEBUG|INFO|WARNING|ERROR  (default INFO)
    LOG_FORMAT  text|json                 (default text)
    LOG_DIR     directory for the rotating log file (default ./logs)

Usage:
    from logging_setup import configure_logging, get_logger
    configure_logging()
    logger = get_logger(__name__)
    logger.info("Starting export", extra={"export_name": "daily_transactions"})
"""
import json
import logging
import logging.handlers
import os
from datetime import datetime, timezone

_EXTRA_FIELDS = ("export_name", "status", "row_count", "duration_ms")

_configured = False


class JSONFormatter(logging.Formatter):
    """Emits one JSON object per log line, easy to ship to ELK/Loki."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for key in _EXTRA_FIELDS:
            if hasattr(record, key):
                payload[key] = getattr(record, key)
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def configure_logging():
    """Call once at startup (export.py's main()). Safe to call more than once."""
    global _configured
    if _configured:
        return
    _configured = True

    level = getattr(logging, os.environ.get("LOG_LEVEL", "INFO").upper(), logging.INFO)
    fmt = os.environ.get("LOG_FORMAT", "text").lower()
    log_dir = os.environ.get("LOG_DIR", "./logs")

    formatter = (
        JSONFormatter()
        if fmt == "json"
        else logging.Formatter("%(asctime)s [%(levelname)-8s] %(name)s | %(message)s", "%Y-%m-%d %H:%M:%S")
    )

    root = logging.getLogger()
    root.setLevel(level)
    for h in root.handlers[:]:
        root.removeHandler(h)

    console_h = logging.StreamHandler()
    console_h.setFormatter(formatter)
    root.addHandler(console_h)

    os.makedirs(log_dir, exist_ok=True)
    file_h = logging.handlers.RotatingFileHandler(
        os.path.join(log_dir, "export.log"),
        maxBytes=10 * 1024 * 1024,   # 10 MB
        backupCount=5,
        encoding="utf-8",
    )
    file_h.setFormatter(formatter)
    root.addHandler(file_h)

    # Quieten noisy third-party loggers
    logging.getLogger("paramiko").setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    """Return a logger. configure_logging() must have been called first."""
    return logging.getLogger(name)
