"""Loads export definitions from the export_definitions table (replaces
definitions.yaml). Same SQLAlchemy Core style as tracking.py.

Usage:
    from definitions_repo import load_definitions
    definitions = load_definitions()   # {name: {...}}
"""
import json
import os
from typing import Optional

from sqlalchemy import create_engine, text

_engine = None


def _get_engine():
    global _engine
    if _engine is None:
        _engine = create_engine(os.environ["DATABASE_URL"])
    return _engine


def _parse_json(value):
    """psycopg2 deserializes JSONB to native Python objects already; this
    only kicks in for drivers/backends that hand back a raw JSON string."""
    if value is None or not isinstance(value, str):
        return value
    return json.loads(value) if value else None


def load_definitions(include_inactive: bool = False) -> dict:
    """Returns {name: definition_dict}, shaped exactly like the old
    definitions.yaml entries (name, description, query, format,
    remote_filename, delivery, email_to, zip, format_config)."""
    engine = _get_engine()
    where_clause = "" if include_inactive else "WHERE is_active = TRUE"
    with engine.connect() as conn:
        rows = conn.execute(text(f"""
            SELECT name, description, query, format, remote_filename,
                   delivery, email_to, zip, format_config
            FROM export_definitions
            {where_clause}
            ORDER BY name
        """)).mappings().all()

    definitions = {}
    for row in rows:
        d = dict(row)
        d["email_to"] = _parse_json(d.get("email_to"))
        d["format_config"] = _parse_json(d.get("format_config"))
        definitions[d["name"]] = d
    return definitions


def get_definition(name: str) -> Optional[dict]:
    return load_definitions(include_inactive=True).get(name)
