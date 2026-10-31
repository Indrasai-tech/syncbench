from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI

from app.api import reports, runs, scenarios
from app.core.logging import setup_logging
from app.core.security import require_api_key
from app.db.session import Base, engine
from app.engine.loader import load_scenarios
from app.models import run as _run_models  # noqa: F401  (register tables)


@asynccontextmanager
async def lifespan(_: FastAPI):
    setup_logging()
    load_scenarios()  # fail fast if any scenario file is invalid
    Base.metadata.create_all(engine)
    yield


app = FastAPI(title="SyncBench API", version="0.1.0", lifespan=lifespan)


@app.get("/health")
def health():
    return {"status": "ok", "service": "syncbench", "scenarios": len(load_scenarios())}


for router in (scenarios.router, runs.router, reports.router):
    app.include_router(router, prefix="/api/v1", dependencies=[Depends(require_api_key)])
