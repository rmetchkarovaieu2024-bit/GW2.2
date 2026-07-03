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
import zipfile
from datetime import date

import yaml
from dotenv import load_dotenv

from db import run_query
from exporters import csv_exporter, excel_exporter
from delivery import sftp_delivery, email_delivery
from logging_setup import configure_logging, get_logger, ExportLogContext
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


def zip_export_file(local_path: str, remote_filename: str) -> tuple:
    """Zips local_path (arcname = remote_filename). Returns (zip_local_path, zip_remote_filename)."""
    zip_local_path = f"{local_path}.zip"
    zip_remote_filename = f"{remote_filename}.zip"
    with zipfile.ZipFile(zip_local_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(local_path, arcname=remote_filename)
    return zip_local_path, zip_remote_filename


def run_export(definition: dict, output_dir: str, upload: bool = True, triggered_by: str = "manual"):
    name = definition["name"]
    fmt = definition["format"]
    if fmt not in EXPORTERS:
        raise ValueError(f"Unknown format '{fmt}' for export '{name}' (use 'csv' or 'excel')")

    delivery = definition.get("delivery", "sftp")
    if delivery not in ("sftp", "email"):
        raise ValueError(f"Unknown delivery '{delivery}' for export '{name}' (use 'sftp' or 'email')")
    if delivery == "email" and not definition.get("email_to"):
        raise ValueError(f"Export '{name}' has delivery: email but no email_to recipients configured")

    run = tracking.start_run(name, triggered_by=triggered_by)
    with ExportLogContext(export_name=name):
        try:
            logger.info("running query...")
            df = run_query(definition["query"])
            logger.info(f"got {len(df)} rows", extra={"row_count": len(df)})

            remote_filename = definition["remote_filename"].format(date=date.today().isoformat())
            local_path = os.path.join(output_dir, remote_filename)
            os.makedirs(output_dir, exist_ok=True)

            logger.info(f"writing {fmt} -> {local_path}")
            EXPORTERS[fmt].export(df, local_path, definition.get("format_config"))

            remote_path = None
            if upload:
                deliver_path, deliver_filename = local_path, remote_filename
                if definition.get("zip", False):
                    deliver_path, deliver_filename = zip_export_file(local_path, remote_filename)
                    logger.info(f"zipped -> {deliver_path}")

                if delivery == "email":
                    recipients = definition["email_to"]
                    logger.info(f"emailing to {', '.join(recipients)} -> {deliver_filename}")
                    remote_path = email_delivery.send(deliver_path, deliver_filename, recipients)
                    logger.info(f"done. Sent to: {remote_path}")
                else:
                    logger.info(f"uploading via SFTP -> {deliver_filename}")
                    remote_path = sftp_delivery.upload(deliver_path, deliver_filename)
                    logger.info(f"done. Remote path: {remote_path}")
            else:
                logger.info(f"done. Local path: {local_path}")

            tracking.mark_success(run, row_count=len(df), file_path=local_path, remote_path=remote_path)
        except Exception as exc:
            logger.exception(f"export failed: {exc}")
            tracking.mark_failed(run, str(exc))
            raise


def main():
    load_dotenv()
    configure_logging()

    parser = argparse.ArgumentParser(description="Run an on-demand CSV/Excel export and deliver it via SFTP or email.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--name", help="Name of a single export to run (see definitions.yaml)")
    group.add_argument("--all", action="store_true", help="Run every export defined in definitions.yaml")
    group.add_argument("--list", action="store_true", help="List available export names and exit")
    parser.add_argument("--local-only", action="store_true", help="Write export output locally only; skip SFTP/email delivery")
    args = parser.parse_args()

    definitions = load_definitions()

    if args.list:
        for name, d in definitions.items():
            print(f"{name}  [{d['format']}/{d.get('delivery', 'sftp')}]  {d.get('description', '')}")
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
