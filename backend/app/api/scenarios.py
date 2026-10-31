from fastapi import APIRouter, HTTPException

from app.engine.loader import load_scenarios

router = APIRouter(prefix="/scenarios", tags=["scenarios"])


@router.get("")
def list_scenarios():
    return [
        {"id": s.id, "name": s.name, "description": s.description, "policy": s.policy,
         "synchronizer": s.synchronizer, "operation_count": len(s.operations),
         "failure_count": len(s.failures), "assertions": s.assertions}
        for s in load_scenarios().values()
    ]


@router.get("/{scenario_id}")
def get_scenario(scenario_id: str):
    scenario = load_scenarios().get(scenario_id)
    if scenario is None:
        raise HTTPException(404, f"Scenario '{scenario_id}' not found")
    return scenario.model_dump()
