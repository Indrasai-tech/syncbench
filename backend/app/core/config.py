from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path


def _db_url() -> str:
    url = os.getenv("DATABASE_URL", "sqlite:///./syncbench.db")
    if url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql+psycopg://", 1)
    return url


def _scenarios_dir() -> Path:
    env = os.getenv("SCENARIOS_DIR")
    if env:
        return Path(env)
    return Path(__file__).resolve().parents[3] / "scenarios"


@dataclass(frozen=True)
class Settings:
    database_url: str = field(default_factory=_db_url)
    scenarios_dir: Path = field(default_factory=_scenarios_dir)


settings = Settings()
