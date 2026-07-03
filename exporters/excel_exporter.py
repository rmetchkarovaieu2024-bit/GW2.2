import pandas as pd
from typing import Optional


def export(df: pd.DataFrame, output_path: str, config: Optional[dict] = None) -> str:
    config = config or {}
    df.to_excel(
        output_path,
        index=False,
        engine="openpyxl",
        sheet_name=config.get("sheet_name", "Sheet1"),
    )
    return output_path
