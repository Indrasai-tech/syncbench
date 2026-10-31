from __future__ import annotations

import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.engine.executor import execute_run
from app.engine.loader import load_scenarios
from app.models.run import Run
from app.repositories import event_to_dict, list_events, run_to_dict
from app.schemas.run import RunCreate

router = APIRouter(prefix="/runs", tags=["runs"])


def _get_run(db: Session, run_id: str) -> Run:
    run = db.get(Run, run_id)
    if run is None:
        raise HTTPException(404, f"Run '{run_id}' not found")
    return run


@router.post("", status_code=202)
def create_run(body: RunCreate, background: BackgroundTasks, db: Session = Depends(get_db)):
    scenario = load_scenarios().get(body.scenario_id)
    if scenario is None:
        raise HTTPException(404, f"Scenario '{body.scenario_id}' not found")
    run = Run(
        id=str(uuid.uuid4()),
        scenario_id=scenario.id,
        synchronizer=body.synchronizer or scenario.synchronizer,
        seed=scenario.seed if body.seed is None else body.seed,
        status="queued",
    )
    db.add(run)
    db.commit()
    background.add_task(execute_run, run.id)
    return run_to_dict(run)


@router.get("")
def list_runs(limit: int = Query(50, ge=1, le=200), scenario_id: str | None = None,
              db: Session = Depends(get_db)):
    stmt = select(Run).order_by(Run.created_at.desc()).limit(limit)
    if scenario_id:
        stmt = stmt.where(Run.scenario_id == scenario_id)
    return [run_to_dict(r) for r in db.scalars(stmt)]


@router.get("/{run_id}")
def get_run(run_id: str, db: Session = Depends(get_db)):
    return run_to_dict(_get_run(db, run_id))


@router.get("/{run_id}/events")
def get_events(run_id: str, db: Session = Depends(get_db)):
    _get_run(db, run_id)
    return [event_to_dict(e) for e in list_events(db, run_id)]


@router.post("/{run_id}/cancel")
def cancel_run(run_id: str, db: Session = Depends(get_db)):
    run = _get_run(db, run_id)
    if run.status not in ("queued", "running"):
        raise HTTPException(409, f"Run already finished with status '{run.status}'")
    run.status = "cancelled"
    db.commit()
    return run_to_dict(run)
