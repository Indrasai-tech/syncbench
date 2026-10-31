from __future__ import annotations

from pydantic import BaseModel, Field

from app.schemas.scenario import SynchronizerName


class RunCreate(BaseModel):
    scenario_id: str
    synchronizer: SynchronizerName | None = Field(None, description="Override the scenario default")
    seed: int | None = Field(None, description="Override the scenario seed")
