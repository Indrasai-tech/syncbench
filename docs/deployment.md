# Deployment

1. Build and deploy `backend/Dockerfile` using the repository root as build context.
2. Configure `API_KEY` with a long random secret and provide durable storage mounted at `/app/data`.
3. Set `PORT` to the platform's assigned port. `SCENARIOS_DIR` defaults to `/app/scenarios` in the image.
4. Verify `GET /health`, then call `/api/v1/scenarios` with `X-API-Key`.
5. In the iOS app, set the service's HTTPS URL and API key in Settings.
6. Use `/api/v1/runs/compare` to compare synchronizers, or submit persisted runs individually.

The bundled JSON file store is for a single API process. For multiple replicas or sustained concurrent writes, replace it with a shared database-backed store and add proxy rate limits before public exposure.
