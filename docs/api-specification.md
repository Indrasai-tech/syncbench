# API specification

Base path `/api/v1`. When `API_KEY` is set, send `X-API-Key: <key>` (not required for `/health`).

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/health` | Health check (no auth) |
| GET | `/api/v1/scenarios` | List scenarios |
| GET | `/api/v1/scenarios/{id}` | Full scenario |
| POST | `/api/v1/scenarios/validate` | Validate a scenario body without starting a run |
| POST | `/api/v1/runs` | Start a run. Body: `{"scenario_id", "synchronizer"?: "reference"\|"naive", "seed"?: int}` -> 202 |
| POST | `/api/v1/runs/compare` | Run both synchronizers against one scenario without storing the reports |
| GET | `/api/v1/runs?limit=50&offset=0&scenario_id=&status=` | Run history, newest first |
| GET | `/api/v1/runs/export.csv` | Export saved run metadata as CSV |
| GET | `/api/v1/runs/{id}` | Status and summary |
| GET | `/api/v1/runs/{id}/events` | Event timeline |
| GET | `/api/v1/runs/{id}/events?after_seq=0&limit=200` | Event timeline page |
| GET | `/api/v1/runs/{id}/report?format=json\|markdown` | Completed report (409 if not ready) |
| POST | `/api/v1/runs/{id}/cancel` | Cancel a queued/running run (409 if finished) |
| POST | `/api/v1/runs/{id}/replay` | Re-run with the original scenario, synchronizer, and seed (202) |
| GET | `/api/v1/stats` | Totals for the dashboard |

Run status: `queued -> running -> passed | failed | cancelled | error`.
Errors use `{"detail": "..."}`. API-key authentication can be disabled for local-only development by leaving `API_KEY` empty.
