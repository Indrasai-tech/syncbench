"""Executes a stored run: loads the scenario, runs it, persists report + events."""
from __future__ import annotations

import logging
from datetime import datetime, timezone

from app.db.session import SessionLocal
from app.engine.loader import load_scenarios
from app.engine.runner import run_scenario
from app.models.run import Run, RunEvent

log = logging.getLogger("syncbench.executor")


def execute_run(run_id: str) -> None:
    with SessionLocal() as db:
        run = db.get(Run, run_id)
        if run is None or run.status != "queued":  # cancelled before it started
            return
        run.status = "running"
        db.commit()

        def cancelled() -> bool:
            with SessionLocal() as check:
                current = check.get(Run, run_id)
                return current is not None and current.status == "cancelled"

        try:
            scenario = load_scenarios()[run.scenario_id]
            report = run_scenario(scenario, run.synchronizer, run.seed, should_cancel=cancelled)
        except Exception as exc:  # noqa: BLE001 - record any failure instead of losing the run
            log.exception("run %s crashed", run_id)
            db.refresh(run)
            run.status, run.error = "error", str(exc)
            run.finished_at = datetime.now(timezone.utc)
            db.commit()
            return

        db.refresh(run)
        if run.status == "cancelled":
            return
        for e in report["events"]:
            db.add(RunEvent(run_id=run_id, seq=e["seq"], t_ms=e["t_ms"], actor=e["actor"],
                            type=e["type"], detail=e["detail"]))
        run.status = report["status"]
        run.report = report
        run.duration_ms = report["metrics"]["wall_ms"]
        run.summary = {**report["metrics"], "fingerprint": report["fingerprint"]}
        run.finished_at = datetime.now(timezone.utc)
        db.commit()
