from __future__ import annotations

import json
from pathlib import Path

from app.core.config import settings
from app.schemas.scenario import Scenario


def load_scenarios(directory: Path | None = None) -> dict[str, Scenario]:
    directory = directory or settings.scenarios_dir
    scenarios: dict[str, Scenario] = {}
    for path in sorted(Path(directory).glob("*.json")):
        scenario = Scenario.model_validate(json.loads(path.read_text(encoding="utf-8")))
        if scenario.id in scenarios:
            raise ValueError(f"duplicate scenario id '{scenario.id}' in {path.name}")
        scenarios[scenario.id] = scenario
    return scenarios
