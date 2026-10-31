"""Assertion engine: compares expected vs actual state and detects lost updates / duplicate effects."""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from typing import Any

from app.engine.synchronizer import BaseServer, SyncClient
from app.schemas.scenario import MATCH_SUFFIX, Scenario


@dataclass
class Context:
    scenario: Scenario
    server: BaseServer
    clients: dict[str, SyncClient]
    events: list[dict[str, Any]]


def find_duplicate_effects(server: BaseServer) -> dict[str, int]:
    counts = Counter(e["op_id"] for e in server.effects)
    return {op_id: n for op_id, n in counts.items() if n > 1}


def find_lost_updates(server: BaseServer) -> list[dict[str, Any]]:
    """A field is 'lost' when the last applied update to it is not what the server finally holds."""
    last: dict[str, dict[str, Any]] = {}
    for e in server.effects:
        if e["kind"] == "update":
            last[e["field"]] = e
    lost = []
    for field, effect in last.items():
        if server.state.get(field) != effect["value"]:
            lost.append({"field": field, "op_id": effect["op_id"], "expected": effect["value"],
                         "actual": server.state.get(field)})
    return lost


def _seqs(ctx: Context, *, field: str | None = None, op_ids: set[str] | None = None) -> list[int]:
    out = []
    for ev in ctx.events:
        d = ev["detail"]
        if (field is not None and d.get("field") == field) or (op_ids and d.get("op_id") in op_ids):
            out.append(ev["seq"])
    return out


def _result(name: str, passed: bool, expected: Any, actual: Any, message: str, seqs: list[int]) -> dict:
    return {"name": name, "passed": passed, "expected": expected, "actual": actual,
            "message": message, "event_seqs": [] if passed else seqs}


def evaluate(ctx: Context) -> list[dict[str, Any]]:
    results = []
    for name in ctx.scenario.assertions:
        if name == "no_duplicate_business_effects":
            dups = find_duplicate_effects(ctx.server)
            results.append(_result(
                name, not dups, "each operation applied at most once", dups or "no duplicates",
                "OK" if not dups else f"Operations applied more than once: {dups}",
                _seqs(ctx, op_ids=set(dups))))
        elif name == "no_lost_updates":
            lost = find_lost_updates(ctx.server)
            fields = {item["field"] for item in lost}
            results.append(_result(
                name, not lost, "final value equals last applied update", lost or "none lost",
                "OK" if not lost else "Updates were overwritten after being applied: "
                + ", ".join(sorted(fields)),
                [s for f in fields for s in _seqs(ctx, field=f)]))
        elif name == "all_operations_acknowledged":
            pending = {c.id: [o.op_id for o in c.pending] for c in ctx.clients.values() if c.pending}
            results.append(_result(
                name, not pending, "no pending operations", pending or "none pending",
                "OK" if not pending else f"Operations never acknowledged: {pending}",
                [s for ids in pending.values() for s in _seqs(ctx, op_ids=set(ids))]))
        elif name == "final_state_matches_expected":
            expected = ctx.scenario.expected_final_state
            actual = {k: ctx.server.state.get(k) for k in expected}
            ok = actual == expected
            results.append(_result(name, ok, expected, actual,
                                   "OK" if ok else "Final server state differs from expected", []))
        elif name.endswith(MATCH_SUFFIX):
            field = name[: -len(MATCH_SUFFIX)]
            expected = ctx.scenario.expected_final_state[field]
            actual = ctx.server.state.get(field)
            ok = actual == expected
            results.append(_result(
                name, ok, expected, actual,
                "OK" if ok else f"'{field}' expected {expected!r} but server has {actual!r}",
                _seqs(ctx, field=field)))
    return results
