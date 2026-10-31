# Testing guide

- Backend: `cd backend && pytest -q` (SQLite, no Docker needed). Covers scenario validation, failure injection,
  assertions, reproducibility, every scenario against both synchronizers, and the REST API.
- Comparison table: `python scripts/compare_implementations.py --write docs/comparison-results.md`
- iOS: `ModelTests` (JSON decoding) and `APIClientTests` (URL building, headers, error mapping with a mocked URLProtocol). Run with Cmd+U.
- **Add a scenario:** drop a JSON file in `scenarios/`; `test_engine.py` automatically checks the reference synchronizer passes it.
- **Measurements to publish:** scenarios executed, correct pass/fail classification (reference passes all, naive fails the
  expected ones), lost updates, duplicate effects, retries, wall time, and fingerprint equality across repeated runs.
