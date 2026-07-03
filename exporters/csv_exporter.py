import pandas as pd
from typing import Optional


def export(df: pd.DataFrame, output_path: str, config: Optional[dict] = None) -> str:
    config = config or {}
    df.to_csv(
        output_path,
        index=False,
        sep=config.get("delimiter", ","),
        encoding=config.get("encoding", "utf-8"),
    )
    return output_path
