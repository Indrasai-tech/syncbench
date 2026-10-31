"""Two synchronization implementations that SyncBench can test.

ReferenceServer: per-field versions, idempotency keys, policy-based conflict handling.
NaiveServer:     overwrites the whole record with the client's copy and has no idempotency.
                 It exists to prove that SyncBench really detects failures.
"""
from __future__ import annotations

import copy
from dataclasses import dataclass
from typing import Any


@dataclass
class PendingOp:
    op_id: str
    client: str
    kind: str  # "update" | "increment"
    field: str
    value: Any
    base_version: int = 1


@dataclass
class OpResult:
    op_id: str
    field: str
    status: str  # applied | duplicate_ignored | conflict_rejected | conflict_resolved_lww


@dataclass
class PushResponse:
    results: list[OpResult]
    state: dict[str, Any]
    versions: dict[str, int]


class BaseServer:
    name = "base"

    def __init__(self, initial: dict[str, Any], policy: str) -> None:
        self.state: dict[str, Any] = copy.deepcopy(initial)
        self.policy = policy
        self.field_versions: dict[str, int] = {k: 1 for k in initial}
        self.effects: list[dict[str, Any]] = []  # every business effect, in order
        self._server_seq = 0

    def _record(self, op_id: str, client: str, kind: str, field: str, value: Any) -> None:
        self.effects.append(
            {"op_id": op_id, "client": client, "kind": kind, "field": field, "value": value}
        )

    def server_update(self, field: str, value: Any) -> str:
        self._server_seq += 1
        op_id = f"server-{self._server_seq}"
        self.state[field] = value
        self.field_versions[field] = self.field_versions.get(field, 0) + 1
        self._record(op_id, "server", "update", field, value)
        return op_id

    def receive(self, client: str, ops: list[PendingOp], local_state: dict[str, Any]) -> PushResponse:
        raise NotImplementedError


class ReferenceServer(BaseServer):
    name = "reference"

    def __init__(self, initial: dict[str, Any], policy: str) -> None:
        super().__init__(initial, policy)
        self._seen: dict[str, str] = {}

    def receive(self, client: str, ops: list[PendingOp], local_state: dict[str, Any]) -> PushResponse:
        results: list[OpResult] = []
        for op in ops:
            if op.op_id in self._seen:
                results.append(OpResult(op.op_id, op.field, "duplicate_ignored"))
                continue
            status = self._apply(op)
            self._seen[op.op_id] = status
            results.append(OpResult(op.op_id, op.field, status))
        return PushResponse(results, copy.deepcopy(self.state), dict(self.field_versions))

    def _apply(self, op: PendingOp) -> str:
        if op.kind == "increment":  # commutative: never conflicts
            self._write(op, self.state.get(op.field, 0) + op.value)
            return "applied"
        current = self.field_versions.get(op.field, 0)
        if op.base_version < current:  # someone changed this field since the client's base
            if self.policy == "last_write_wins":
                self._write(op, op.value)
                return "conflict_resolved_lww"
            return "conflict_rejected"  # server_wins / merge_non_overlapping_fields
        self._write(op, op.value)
        return "applied"

    def _write(self, op: PendingOp, new_value: Any) -> None:
        self.state[op.field] = new_value
        self.field_versions[op.field] = self.field_versions.get(op.field, 0) + 1
        self._record(op.op_id, op.client, op.kind, op.field, op.value)


class NaiveServer(BaseServer):
    name = "naive"

    def receive(self, client: str, ops: list[PendingOp], local_state: dict[str, Any]) -> PushResponse:
        results: list[OpResult] = []
        for op in ops:
            if op.kind == "increment":
                self.state[op.field] = self.state.get(op.field, 0) + op.value
            else:  # whole-record overwrite: silently destroys other clients' edits
                self.state = copy.deepcopy(local_state)
            self._record(op.op_id, op.client, op.kind, op.field, op.value)
            results.append(OpResult(op.op_id, op.field, "applied"))
        return PushResponse(results, copy.deepcopy(self.state), {})


def make_server(name: str, initial: dict[str, Any], policy: str) -> BaseServer:
    return {"reference": ReferenceServer, "naive": NaiveServer}[name](initial, policy)


class SyncClient:
    """A simulated device with a local copy and a queue of pending operations."""

    def __init__(self, client_id: str, initial: dict[str, Any], versions: dict[str, int]) -> None:
        self.id = client_id
        self.local: dict[str, Any] = copy.deepcopy(initial)
        self.versions: dict[str, int] = dict(versions)
        self.pending: list[PendingOp] = []
        self.online = True
        self._counter = 0

    def edit(self, kind: str, field: str, value: Any) -> PendingOp:
        self._counter += 1
        op = PendingOp(
            op_id=f"{self.id}-{self._counter}",
            client=self.id,
            kind=kind,
            field=field,
            value=value,
            base_version=self.versions.get(field, 1),
        )
        if kind == "increment":
            self.local[field] = self.local.get(field, 0) + value
        else:
            self.local[field] = value
        self.pending.append(op)
        return op

    def acknowledge(self, results: list[OpResult]) -> None:
        acked = {r.op_id for r in results}
        self.pending = [o for o in self.pending if o.op_id not in acked]

    def pull(self, response: PushResponse) -> None:
        pending_fields = {o.field for o in self.pending}
        for key, value in response.state.items():
            if key not in pending_fields:
                self.local[key] = copy.deepcopy(value)
        if response.versions:
            self.versions = dict(response.versions)
