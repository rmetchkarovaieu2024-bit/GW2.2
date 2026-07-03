"""Runs a SQL query and returns the result as a pandas DataFrame."""
import os
import pandas as pd
from sqlalchemy import create_engine, text


def run_query(query: str) -> pd.DataFrame:
    database_url = os.environ["DATABASE_URL"]
    engine = create_engine(database_url)
    with engine.connect() as conn:
        result = conn.execute(text(query))
        rows = result.fetchall()
        columns = result.keys()
    return pd.DataFrame(rows, columns=columns)
