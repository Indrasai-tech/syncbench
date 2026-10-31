from app.engine.assertions import find_duplicate_effects, find_lost_updates
from app.engine.loader import load_scenarios
from app.engine.runner import run_scenario
from app.engine.synchronizer import NaiveServer, ReferenceServer, PendingOp

SC = load_scenarios()


def test_duplicate_effects_detected():
    s = NaiveServer({"count": 0}, "server_wins")
    op = PendingOp("A-1", "A", "increment", "count", 1)
    s.receive("A", [op], {"count": 1})
    s.receive("A", [op], {"count": 1})
    assert find_duplicate_effects(s) == {"A-1": 2}


def test_reference_server_is_idempotent():
    s = ReferenceServer({"count": 0}, "server_wins")
    op = PendingOp("A-1", "A", "increment", "count", 1)
    s.receive("A", [op], {})
    r = s.receive("A", [op], {})
    assert r.results[0].status == "duplicate_ignored"
    assert s.state["count"] == 1 and not find_duplicate_effects(s)


def test_lost_update_detected_with_naive_overwrite():
    report = run_scenario(SC["concurrent-field-updates"], "naive")
    assert report["metrics"]["lost_updates"] == 1
    failed = [a for a in report["assertions"] if not a["passed"]]
    assert {a["name"] for a in failed} >= {"status_matches_expected", "no_lost_updates"}
    assert all(a["event_seqs"] for a in failed)  # failures point at the relevant events


def test_last_write_wins_policy_applies_conflicting_write():
    s = ReferenceServer({"status": "open"}, "last_write_wins")
    s.server_update("status", "cancelled")
    r = s.receive("A", [PendingOp("A-1", "A", "update", "status", "completed", base_version=1)], {})
    assert r.results[0].status == "conflict_resolved_lww" and s.state["status"] == "completed"


def test_find_lost_updates_empty_for_clean_server():
    s = ReferenceServer({"status": "open"}, "server_wins")
    s.server_update("status", "x")
    assert find_lost_updates(s) == []
