from __future__ import annotations

from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.run import Run, RunEvent


def run_to_dict(run: Run) -> dict[str, Any]:
    return {
        "id": run.id,
        "scenario_id": run.scenario_id,
        "synchronizer": run.synchronizer,
        "seed": run.seed,
        "status": run.status,
        "created_at": run.created_at.isoformat() if run.created_at else None,
        "finished_at": run.finished_at.isoformat() if run.finished_at else None,
        "duration_ms": run.duration_ms,
        "summary": run.summary,
        "error": run.error,
    }


def event_to_dict(e: RunEvent) -> dict[str, Any]:
    return {"seq": e.seq, "t_ms": e.t_ms, "actor": e.actor, "type": e.type, "detail": e.detail}


def list_events(db: Session, run_id: str) -> list[RunEvent]:
    return list(db.scalars(select(RunEvent).where(RunEvent.run_id == run_id).order_by(RunEvent.seq)))
