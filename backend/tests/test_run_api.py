import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture()
def client():
    with TestClient(app) as c:
        yield c


def _run(client, scenario_id, synchronizer=None):
    body = {"scenario_id": scenario_id, **({"synchronizer": synchronizer} if synchronizer else {})}
    r = client.post("/api/v1/runs", json=body)
    assert r.status_code == 202
    return r.json()["id"]


def test_list_and_get_scenarios(client):
    items = client.get("/api/v1/scenarios").json()
    assert len(items) >= 5
    assert client.get("/api/v1/scenarios/duplicate-request").json()["policy"]
    assert client.get("/api/v1/scenarios/nope").status_code == 404


def test_passing_run_end_to_end(client):
    run_id = _run(client, "concurrent-field-updates", "reference")
    run = client.get(f"/api/v1/runs/{run_id}").json()
    assert run["status"] == "passed"
    events = client.get(f"/api/v1/runs/{run_id}/events").json()
    assert events[0]["type"] == "run_started" and events[-1]["type"] == "run_finished"
    report = client.get(f"/api/v1/runs/{run_id}/report").json()
    assert report["final_server_state"]["status"] == "completed"


def test_failing_run_produces_useful_report(client):
    run_id = _run(client, "duplicate-request", "naive")
    assert client.get(f"/api/v1/runs/{run_id}").json()["status"] == "failed"
    report = client.get(f"/api/v1/runs/{run_id}/report").json()
    failed = [a for a in report["assertions"] if not a["passed"]]
    assert failed and report["metrics"]["duplicate_effects"] == 1
    md = client.get(f"/api/v1/runs/{run_id}/report?format=markdown")
    assert md.status_code == 200 and "FAIL" in md.text


def test_same_settings_give_same_fingerprint(client):
    a = client.get(f"/api/v1/runs/{_run(client, 'retry-after-timeout')}").json()
    b = client.get(f"/api/v1/runs/{_run(client, 'retry-after-timeout')}").json()
    assert a["summary"]["fingerprint"] == b["summary"]["fingerprint"]


def test_unknown_scenario_and_run(client):
    assert client.post("/api/v1/runs", json={"scenario_id": "nope"}).status_code == 404
    assert client.get("/api/v1/runs/not-a-run").status_code == 404
    assert client.get("/api/v1/runs/not-a-run/events").status_code == 404


def test_cancel_finished_run_conflicts(client):
    run_id = _run(client, "offline-edit-reconnect")
    assert client.post(f"/api/v1/runs/{run_id}/cancel").status_code == 409


def test_history_and_stats(client):
    _run(client, "offline-edit-reconnect", "reference")
    _run(client, "concurrent-field-updates", "naive")
    assert len(client.get("/api/v1/runs?limit=5").json()) >= 2
    stats = client.get("/api/v1/stats").json()
    assert stats["total_runs"] >= 2 and stats["lost_updates_detected"] >= 1


def test_api_key_enforced_when_configured(client, monkeypatch):
    monkeypatch.setenv("API_KEY", "secret")
    assert client.get("/api/v1/scenarios").status_code == 401
    assert client.get("/api/v1/scenarios", headers={"X-API-Key": "wrong"}).status_code == 401
    assert client.get("/api/v1/scenarios", headers={"X-API-Key": "secret"}).status_code == 200
    assert client.get("/health").status_code == 200
