#!/usr/bin/env python3
"""
On-demand export CLI.

Usage:
    python export.py --list
    python export.py --name example_export
    python export.py --all
"""
import argparse
import os
import sys
from datetime import date

import yaml
from dotenv import load_dotenv

from db import run_query
from exporters import csv_exporter, excel_exporter
from delivery import sftp_delivery
from logging_setup import configure_logging, get_logger
import tracking

EXPORTERS = {
    "csv": csv_exporter,
    "excel": excel_exporter,
}

DEFINITIONS_PATH = os.path.join(os.path.dirname(__file__), "definitions.yaml")

logger = get_logger(__name__)


def load_definitions():
    with open(DEFINITIONS_PATH) as f:
        data = yaml.safe_load(f)
    return {d["name"]: d for d in data["exports"]}


def run_export(definition: dict, output_dir: str, upload: bool = True, triggered_by: str = "manual"):
    name = definition["name"]
    fmt = definition["format"]
    if fmt not in EXPORTERS:
        raise ValueError(f"Unknown format '{fmt}' for export '{name}' (use 'csv' or 'excel')")

    run = tracking.start_run(name, triggered_by=triggered_by)
    try:
        logger.info(f"[{name}] running query...", extra={"export_name": name})
        df = run_query(definition["query"])
        logger.info(f"[{name}] got {len(df)} rows", extra={"export_name": name, "row_count": len(df)})

        remote_filename = definition["remote_filename"].format(date=date.today().isoformat())
        local_path = os.path.join(output_dir, remote_filename)
        os.makedirs(output_dir, exist_ok=True)

        logger.info(f"[{name}] writing {fmt} -> {local_path}", extra={"export_name": name})
        EXPORTERS[fmt].export(df, local_path, definition.get("format_config"))

        remote_path = None
        if upload:
            logger.info(f"[{name}] uploading via SFTP -> {remote_filename}", extra={"export_name": name})
            remote_path = sftp_delivery.upload(local_path, remote_filename)
            logger.info(f"[{name}] done. Remote path: {remote_path}", extra={"export_name": name, "status": "success"})
        else:
            logger.info(f"[{name}] done. Local path: {local_path}", extra={"export_name": name, "status": "success"})

        tracking.mark_success(run, row_count=len(df), file_path=local_path, remote_path=remote_path)
    except Exception as exc:
        logger.exception(f"[{name}] export failed: {exc}", extra={"export_name": name, "status": "failed"})
        tracking.mark_failed(run, str(exc))
        raise


def main():
    load_dotenv()
    configure_logging()

    parser = argparse.ArgumentParser(description="Run an on-demand CSV/Excel export and deliver it over SFTP.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--name", help="Name of a single export to run (see definitions.yaml)")
    group.add_argument("--all", action="store_true", help="Run every export defined in definitions.yaml")
    group.add_argument("--list", action="store_true", help="List available export names and exit")
    parser.add_argument("--local-only", action="store_true", help="Write export output locally only; skip SFTP upload")
    args = parser.parse_args()

    definitions = load_definitions()

    if args.list:
        for name, d in definitions.items():
            print(f"{name}  [{d['format']}]  {d.get('description', '')}")
        return

    output_dir = os.environ.get("LOCAL_OUTPUT_DIR", "./output")
    upload = not args.local_only

    if args.all:
        targets = list(definitions.values())
    else:
        if args.name not in definitions:
            print(f"Unknown export name '{args.name}'. Use --list to see options.", file=sys.stderr)
            sys.exit(1)
        targets = [definitions[args.name]]

    for definition in targets:
        run_export(definition, output_dir, upload=upload)


if __name__ == "__main__":
    main()
