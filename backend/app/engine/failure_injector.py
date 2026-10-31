"""Deterministic failure injection. All randomness comes from a seeded Random."""
from __future__ import annotations

import random
from dataclasses import dataclass, field

from app.schemas.scenario import Failure


@dataclass
class FaultPlan:
    delay_ms: int = 0
    drop_request: bool = False  # request never reaches the server (timeout)
    unavailable: bool = False  # server answers 503 without processing
    drop_response: bool = False  # server processes, response is lost
    duplicate: bool = False  # network delivers the request twice
    applied: list[str] = field(default_factory=list)


class FailureInjector:
    def __init__(self, failures: list[Failure], seed: int) -> None:
        self.failures = failures
        self.rng = random.Random(seed)

    def plan(self, client: str, sync_no: int, attempt: int) -> FaultPlan:
        plan = FaultPlan()
        for f in self.failures:
            if f.client not in ("*", client) or f.on_sync != sync_no or f.on_attempt != attempt:
                continue
            plan.applied.append(f.type)
            if f.type == "delay":
                jitter = self.rng.randint(0, f.jitter_ms) if f.jitter_ms else 0
                plan.delay_ms += f.delay_ms + jitter
            elif f.type == "timeout":
                plan.drop_request = True
            elif f.type == "server_unavailable":
                plan.unavailable = True
            elif f.type == "drop_response":
                plan.drop_response = True
            elif f.type == "duplicate_delivery":
                plan.duplicate = True
        return plan
