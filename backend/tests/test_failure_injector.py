from app.engine.failure_injector import FailureInjector
from app.schemas.scenario import Failure


def test_plan_matches_only_selected_sync_and_attempt():
    inj = FailureInjector([Failure(type="drop_response", client="A", on_sync=1, on_attempt=1)], seed=1)
    assert inj.plan("A", 1, 1).drop_response
    assert not inj.plan("A", 1, 2).drop_response
    assert not inj.plan("A", 2, 1).drop_response
    assert not inj.plan("B", 1, 1).drop_response


def test_wildcard_client():
    inj = FailureInjector([Failure(type="duplicate_delivery", client="*")], seed=1)
    assert inj.plan("anyone", 1, 1).duplicate


def test_jitter_is_deterministic_for_same_seed():
    f = [Failure(type="delay", delay_ms=100, jitter_ms=500)]
    a = [FailureInjector(f, 99).plan("A", 1, 1).delay_ms for _ in range(1)]
    b = [FailureInjector(f, 99).plan("A", 1, 1).delay_ms for _ in range(1)]
    assert a == b and 100 <= a[0] <= 600


def test_different_seeds_can_differ():
    f = [Failure(type="delay", delay_ms=0, jitter_ms=1000)]
    values = {FailureInjector(f, s).plan("A", 1, 1).delay_ms for s in range(20)}
    assert len(values) > 1
