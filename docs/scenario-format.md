# Scenario format

| Field | Meaning |
|---|---|
| `id` | lowercase letters, digits, hyphens |
| `policy` | `merge_non_overlapping_fields`, `server_wins`, `last_write_wins` |
| `synchronizer` | default implementation: `reference` or `naive` |
| `seed`, `max_retries`, `timeout_ms` | determinism and retry settings |
| `initial_state` | starting record (every field used by an operation must exist here) |
| `operations[]` | `client`, `action`, optional `connection`, `field`, `value` |
| `failures[]` | `type`, `client` (or `*`), `on_sync`, `on_attempt`, `delay_ms`, `jitter_ms` |
| `expected_final_state` | what the server must hold at the end |
| `assertions[]` | names listed below |

**Actions:** `update`, `increment` (commutative counter), `sync`, `go_offline`, `go_online`, `server_update` (client `server`).
A `connection` value on any operation switches that client online/offline first.

**Failure types:** `delay`, `timeout` (request lost), `server_unavailable` (503), `drop_response` (server applied it, reply lost), `duplicate_delivery`.

**Assertions:** `<field>_matches_expected`, `final_state_matches_expected`, `no_lost_updates`,
`no_duplicate_business_effects`, `all_operations_acknowledged`.

Files are validated on server startup and in `tests/test_scenarios.py`; an invalid file stops the server from starting.
