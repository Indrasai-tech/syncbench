from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import PlainTextResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.engine.report import report_to_markdown
from app.models.run import Run

router = APIRouter(tags=["reports"])


@router.get("/runs/{run_id}/report")
def get_report(run_id: str, format: str = Query("json", pattern="^(json|markdown)$"),
               db: Session = Depends(get_db)):
    run = db.get(Run, run_id)
    if run is None:
        raise HTTPException(404, f"Run '{run_id}' not found")
    if run.report is None:
        raise HTTPException(409, f"Report not ready (status '{run.status}')")
    if format == "markdown":
        return PlainTextResponse(report_to_markdown(run.report), media_type="text/markdown")
    return run.report


@router.get("/stats")
def stats(db: Session = Depends(get_db)):
    runs = list(db.scalars(select(Run)))
    done = [r for r in runs if r.status in ("passed", "failed")]
    summaries = [r.summary or {} for r in done]
    return {
        "total_runs": len(runs),
        "passed": sum(r.status == "passed" for r in runs),
        "failed": sum(r.status == "failed" for r in runs),
        "errors": sum(r.status == "error" for r in runs),
        "lost_updates_detected": sum(s.get("lost_updates", 0) for s in summaries),
        "duplicate_effects_detected": sum(s.get("duplicate_effects", 0) for s in summaries),
        "total_retries": sum(s.get("retries", 0) for s in summaries),
        "avg_wall_ms": round(sum(r.duration_ms or 0 for r in done) / len(done), 2) if done else 0,
    }
