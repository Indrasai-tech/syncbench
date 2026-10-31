import pytest

from app.engine.loader import load_scenarios
from app.engine.report import report_to_markdown
from app.engine.runner import run_scenario

SC = load_scenarios()


@pytest.mark.parametrize("sid", sorted(SC))
def test_reference_synchronizer_passes_every_scenario(sid):
    report = run_scenario(SC[sid], "reference")
    assert report["status"] == "passed", [a for a in report["assertions"] if not a["passed"]]


def test_naive_passes_only_the_easy_scenario():
    results = {sid: run_scenario(SC[sid], "naive")["status"] for sid in SC}
    assert results["offline-edit-reconnect"] == "passed"
    for sid in ("concurrent-field-updates", "duplicate-request", "retry-after-timeout",
                "server-client-conflict"):
        assert results[sid] == "failed", sid


def test_duplicate_request_naive_double_counts():
    report = run_scenario(SC["duplicate-request"], "naive")
    assert report["final_server_state"]["count"] == 2
    assert report["metrics"]["duplicate_effects"] == 1


def test_retry_scenario_reference_retries_and_stays_safe():
    report = run_scenario(SC["retry-after-timeout"], "reference")
    assert report["metrics"]["retries"] == 1
    assert report["final_server_state"]["count"] == 1
    types = [e["type"] for e in report["events"]]
    assert "response_lost" in types and "op_duplicate_ignored" in types


def test_server_wins_keeps_server_value_and_client_note():
    report = run_scenario(SC["server-client-conflict"], "reference")
    assert report["final_server_state"]["status"] == "cancelled"
    assert report["final_server_state"]["notes"] == "Checked on site"


@pytest.mark.parametrize("sid", sorted(SC))
@pytest.mark.parametrize("mode", ["reference", "naive"])
def test_runs_are_reproducible(sid, mode):
    a = run_scenario(SC[sid], mode)
    b = run_scenario(SC[sid], mode)
    assert a["fingerprint"] == b["fingerprint"]
    assert a["status"] == b["status"]


def test_different_seed_changes_jittered_timing_only():
    a = run_scenario(SC["retry-after-timeout"], "reference", seed=1)
    b = run_scenario(SC["retry-after-timeout"], "reference", seed=2)
    assert a["status"] == b["status"] == "passed"
    assert a["fingerprint"] != b["fingerprint"]


def test_cancellation_stops_the_run():
    report = run_scenario(SC["concurrent-field-updates"], "reference", should_cancel=lambda: True)
    assert report["status"] == "cancelled"


def test_markdown_report_flags_failed_events():
    md = report_to_markdown(run_scenario(SC["duplicate-request"], "naive"))
    assert "FAIL" in md and "related to a failed assertion" in md
