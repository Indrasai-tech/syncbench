import pytest
from pydantic import ValidationError

from app.engine.loader import load_scenarios
from app.schemas.scenario import Scenario


def test_all_five_scenarios_validate():
    scenarios = load_scenarios()
    assert len(scenarios) >= 5
    assert {"offline-edit-reconnect", "concurrent-field-updates", "duplicate-request",
            "retry-after-timeout", "server-client-conflict"} <= set(scenarios)


def _base():
    return {"id": "x", "name": "x", "policy": "server_wins", "initial_state": {"a": 1},
            "operations": [{"client": "c", "action": "update", "field": "a", "value": 2}],
            "expected_final_state": {"a": 2}, "assertions": ["a_matches_expected"]}


def test_valid_minimal_scenario():
    Scenario.model_validate(_base())


@pytest.mark.parametrize("patch", [
    {"assertions": ["bogus_assertion"]},
    {"assertions": ["zzz_matches_expected"]},
    {"policy": "anything_goes"},
    {"id": "Bad ID"},
    {"operations": [{"client": "c", "action": "update", "field": "missing", "value": 1}]},
    {"operations": [{"client": "c", "action": "update", "field": "a"}]},
    {"operations": [{"client": "c", "action": "increment", "field": "a", "value": "x"}]},
    {"failures": [{"type": "delay", "client": "ghost"}]},
    {"operations": []},
])
def test_invalid_scenarios_are_rejected(patch):
    data = {**_base(), **patch}
    with pytest.raises(ValidationError):
        Scenario.model_validate(data)
