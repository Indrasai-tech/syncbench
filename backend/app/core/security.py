import os
import secrets

from fastapi import Header, HTTPException, status


def require_api_key(x_api_key: str | None = Header(default=None)) -> None:
    """If API_KEY is set in the environment, every /api/v1 request must send a matching X-API-Key."""
    expected = os.getenv("API_KEY")
    if not expected:
        return
    if not x_api_key or not secrets.compare_digest(x_api_key, expected):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing or invalid API key")
