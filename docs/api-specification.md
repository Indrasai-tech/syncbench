# API specification

Base path `/api/v1`. If the server has `API_KEY` set, send header `X-API-Key: <key>` (not required for `/health`).
Interactive docs: `/docs`.

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/health` | Health check (no auth) |
| GET | `/api/v1/scenarios` | List scenarios |
| GET | `/api/v1/scenarios/{id}` | Full scenario |
| POST | `/api/v1/runs` | Start a run. Body: `{"scenario_id", "synchronizer"?: "reference"\|"naive", "seed"?: int}` -> 202 |
| GET | `/api/v1/runs?limit=50&scenario_id=` | Run history, newest first |
| GET | `/api/v1/runs/{id}` | Status and summary |
| GET | `/api/v1/runs/{id}/events` | Event timeline |
| GET | `/api/v1/runs/{id}/report?format=json\|markdown` | Completed report (409 if not ready) |
| POST | `/api/v1/runs/{id}/cancel` | Cancel a queued/running run (409 if finished) |
| GET | `/api/v1/stats` | Totals for the dashboard |

Run status: `queued -> running -> passed | failed | cancelled | error`.
Errors use `{"detail": "..."}` with 401, 404, 409, or 422.
