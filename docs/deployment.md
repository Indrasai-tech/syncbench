# Deployment

1. Create a managed PostgreSQL database and a container/web service from `backend/Dockerfile` (build context = repo root).
2. Set secrets in the provider's environment settings, never in git:
   - `DATABASE_URL=postgresql+psycopg://USER:PASSWORD@HOST:5432/DB`
   - `API_KEY=<long random string>` (required for any public deployment)
3. Run command: `uvicorn app.main:app --host 0.0.0.0 --port 8000`. Tables are created on startup.
4. Verify `GET /health`, then call `/api/v1/scenarios` with the `X-API-Key` header.
5. In the iOS app: Settings -> your `https://` URL and API key.
6. Run all scenarios: `python scripts/seed_demo_data.py --base-url https://YOUR_HOST --api-key KEY`.

Before opening it to others: add rate limiting at the proxy (runs are cheap but unbounded), restrict `/docs` if desired,
and add Alembic migrations before changing the schema in production.
