"""Scenario runner. Uses a virtual clock, so runs are fast and fully deterministic."""
from __future__ import annotations

import copy
import hashlib
import json
import time
from collections import defaultdict
from typing import Any, Callable

from app.engine.assertions import Context, evaluate, find_duplicate_effects, find_lost_updates
from app.engine.failure_injector import FailureInjector
from app.engine.synchronizer import SyncClient, make_server
from app.schemas.scenario import Operation, Scenario


class Runner:
    def __init__(self, scenario: Scenario, synchronizer: str, seed: int,
                 should_cancel: Callable[[], bool] | None = None) -> None:
        self.sc = scenario
        self.mode = synchronizer
        self.seed = seed
        self.should_cancel = should_cancel
        self.clock = 0
        self.events: list[dict[str, Any]] = []
        self.server = make_server(synchronizer, scenario.initial_state, scenario.policy)
        self.injector = FailureInjector(scenario.failures, seed)
        self.clients: dict[str, SyncClient] = {}
        self.sync_no: dict[str, int] = defaultdict(int)
        self.retries = 0
        self.cancelled = False

    # ---- helpers -------------------------------------------------------------------
    def log(self, actor: str, type_: str, **detail: Any) -> None:
        self.events.append({"seq": len(self.events) + 1, "t_ms": self.clock,
                            "actor": actor, "type": type_, "detail": detail})

    def _client(self, cid: str) -> SyncClient:
        if cid not in self.clients:
            self.clients[cid] = SyncClient(cid, self.sc.initial_state,
                                           {k: 1 for k in self.sc.initial_state})
        return self.clients[cid]

    def _set_connection(self, c: SyncClient, online: bool) -> None:
        if c.online != online:
            c.online = online
            self.log(c.id, "connection_online" if online else "connection_offline")

    # ---- execution -----------------------------------------------------------------
    def run(self) -> dict[str, Any]:
        wall_start = time.perf_counter()
        self.log("runner", "run_started", scenario=self.sc.id, synchronizer=self.mode,
                 policy=self.sc.policy, seed=self.seed)
        for op in self.sc.operations:
            if self.should_cancel and self.should_cancel():
                self.cancelled = True
                self.log("runner", "run_cancelled")
                break
            self._step(op)
        ctx = Context(self.sc, self.server, self.clients, self.events)
        assertions = evaluate(ctx)
        passed = all(a["passed"] for a in assertions)
        self.log("runner", "run_finished", passed=passed)
        lost = find_lost_updates(self.server)
        dups = find_duplicate_effects(self.server)
        fingerprint = hashlib.sha256(
            json.dumps(self.events, sort_keys=True, default=str).encode()).hexdigest()[:16]
        return {
            "scenario_id": self.sc.id,
            "scenario_name": self.sc.name,
            "synchronizer": self.mode,
            "policy": self.sc.policy,
            "seed": self.seed,
            "status": "cancelled" if self.cancelled else ("passed" if passed else "failed"),
            "assertions": assertions,
            "expected_final_state": self.sc.expected_final_state,
            "final_server_state": copy.deepcopy(self.server.state),
            "metrics": {
                "events": len(self.events),
                "retries": self.retries,
                "lost_updates": len(lost),
                "duplicate_effects": len(dups),
                "assertions_total": len(assertions),
                "assertions_failed": sum(1 for a in assertions if not a["passed"]),
                "simulated_duration_ms": self.clock,
                "wall_ms": round((time.perf_counter() - wall_start) * 1000, 2),
            },
            "fingerprint": fingerprint,
            "events": self.events,
        }

    def _step(self, op: Operation) -> None:
        if op.action == "server_update":
            op_id = self.server.server_update(op.field, op.value)
            self.log("server", "server_update", op_id=op_id, field=op.field, value=op.value)
            return
        c = self._client(op.client)
        if op.connection:
            self._set_connection(c, op.connection == "online")
        if op.action == "go_offline":
            self._set_connection(c, False)
        elif op.action == "go_online":
            self._set_connection(c, True)
        elif op.action in ("update", "increment"):
            pending = c.edit(op.action, op.field, op.value)
            self.log(c.id, "local_edit", op_id=pending.op_id, field=op.field, value=op.value,
                     kind=op.action, offline=not c.online, queued=len(c.pending))
        elif op.action == "sync":
            self._sync(c)

    def _sync(self, c: SyncClient) -> None:
        if not c.online:
            self.log(c.id, "sync_skipped_offline", queued=len(c.pending))
            return
        self.sync_no[c.id] += 1
        for attempt in range(1, self.sc.max_retries + 2):
            plan = self.injector.plan(c.id, self.sync_no[c.id], attempt)
            ops = list(c.pending)
            self.log(c.id, "sync_attempt", attempt=attempt, op_ids=[o.op_id for o in ops],
                     injected=plan.applied)
            if plan.delay_ms:
                self.clock += plan.delay_ms
                self.log("network", "delay", ms=plan.delay_ms)
            if plan.drop_request:
                self.clock += self.sc.timeout_ms
                self.log("network", "request_lost", reason="timeout")
            elif plan.unavailable:
                self.clock += 50
                self.log("server", "server_unavailable", status=503)
            else:
                snapshot = copy.deepcopy(c.local)
                response = self.server.receive(c.id, ops, snapshot)
                self._log_results(response.results)
                if plan.duplicate:
                    dup = self.server.receive(c.id, ops, snapshot)
                    self.log("network", "duplicate_delivered", op_ids=[o.op_id for o in ops])
                    self._log_results(dup.results)
                if plan.drop_response:
                    self.clock += self.sc.timeout_ms
                    self.log("network", "response_lost", reason="timeout")
                else:
                    c.acknowledge(response.results)
                    c.pull(response)
                    self.log(c.id, "sync_complete", attempt=attempt, pending=len(c.pending))
                    return
            if attempt <= self.sc.max_retries:
                self.retries += 1
                backoff = 100 * 2 ** (attempt - 1)
                self.clock += backoff
                self.log(c.id, "retry_scheduled", next_attempt=attempt + 1, backoff_ms=backoff)
        self.log(c.id, "sync_failed", reason="retries_exhausted", pending=len(c.pending))

    def _log_results(self, results: list) -> None:
        for r in results:
            self.log("server", f"op_{r.status}", op_id=r.op_id, field=r.field)


def run_scenario(scenario: Scenario, synchronizer: str | None = None, seed: int | None = None,
                 should_cancel: Callable[[], bool] | None = None) -> dict[str, Any]:
    return Runner(scenario, synchronizer or scenario.synchronizer,
                  scenario.seed if seed is None else seed, should_cancel).run()
