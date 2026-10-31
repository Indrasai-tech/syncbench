"""Scenario file format. Every scenario JSON is validated against these models before it runs."""
from __future__ import annotations

import re
from typing import Any, Literal

from pydantic import BaseModel, Field, model_validator

Policy = Literal["merge_non_overlapping_fields", "server_wins", "last_write_wins"]
Action = Literal["update", "increment", "sync", "go_offline", "go_online", "server_update"]
FailureType = Literal["delay", "timeout", "server_unavailable", "drop_response", "duplicate_delivery"]
SynchronizerName = Literal["reference", "naive"]

STATIC_ASSERTIONS = {
    "no_duplicate_business_effects",
    "no_lost_updates",
    "all_operations_acknowledged",
    "final_state_matches_expected",
}
MATCH_SUFFIX = "_matches_expected"


class Operation(BaseModel):
    client: str
    action: Action
    connection: Literal["online", "offline"] | None = None
    field: str | None = None
    value: Any = None

    @model_validator(mode="after")
    def _check(self) -> "Operation":
        if self.action in ("update", "increment", "server_update") and not self.field:
            raise ValueError(f"action '{self.action}' requires 'field'")
        if self.action in ("update", "server_update") and self.value is None:
            raise ValueError(f"action '{self.action}' requires 'value'")
        if self.action == "increment" and (
            isinstance(self.value, bool) or not isinstance(self.value, (int, float))
        ):
            raise ValueError("action 'increment' requires a numeric 'value'")
        return self


class Failure(BaseModel):
    type: FailureType
    client: str = "*"
    on_sync: int = Field(1, ge=1, description="Applies to the Nth sync call of the client")
    on_attempt: int = Field(1, ge=1, description="Applies to the Nth attempt (retry) of that sync")
    delay_ms: int = Field(0, ge=0, le=60_000)
    jitter_ms: int = Field(0, ge=0, le=60_000)


class Scenario(BaseModel):
    id: str
    name: str
    description: str = ""
    policy: Policy
    synchronizer: SynchronizerName = "reference"
    seed: int = 42
    max_retries: int = Field(3, ge=0, le=10)
    timeout_ms: int = Field(5000, ge=1, le=60_000)
    initial_state: dict[str, Any]
    operations: list[Operation] = Field(min_length=1, max_length=200)
    failures: list[Failure] = Field(default_factory=list)
    expected_final_state: dict[str, Any]
    assertions: list[str] = Field(min_length=1)

    @model_validator(mode="after")
    def _check(self) -> "Scenario":
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", self.id):
            raise ValueError("id must be lowercase letters, digits and hyphens")
        for op in self.operations:
            if op.field and op.action != "sync" and op.field not in self.initial_state:
                raise ValueError(f"operation field '{op.field}' is not in initial_state")
        clients = {op.client for op in self.operations}
        for f in self.failures:
            if f.client != "*" and f.client not in clients:
                raise ValueError(f"failure targets unknown client '{f.client}'")
        for name in self.assertions:
            if name in STATIC_ASSERTIONS:
                continue
            if name.endswith(MATCH_SUFFIX):
                field = name[: -len(MATCH_SUFFIX)]
                if field not in self.expected_final_state:
                    raise ValueError(f"assertion '{name}': '{field}' missing from expected_final_state")
                continue
            raise ValueError(f"unknown assertion '{name}'")
        return self
