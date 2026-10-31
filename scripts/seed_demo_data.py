"""Run every scenario against both synchronizers through the live API, so the iOS app has history.

Usage: python scripts/seed_demo_data.py [--base-url http://127.0.0.1:8000] [--api-key KEY]
"""
import argparse
import time

import httpx


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--base-url", default="http://127.0.0.1:8000")
    p.add_argument("--api-key", default="")
    a = p.parse_args()
    headers = {"X-API-Key": a.api_key} if a.api_key else {}
    with httpx.Client(base_url=a.base_url, headers=headers, timeout=15) as c:
        scenarios = c.get("/api/v1/scenarios").raise_for_status().json()
        for s in scenarios:
            for mode in ("reference", "naive"):
                run = c.post("/api/v1/runs", json={"scenario_id": s["id"], "synchronizer": mode}).json()
                for _ in range(20):
                    run = c.get(f"/api/v1/runs/{run['id']}").json()
                    if run["status"] not in ("queued", "running"):
                        break
                    time.sleep(0.1)
                print(f"{s['id']:28} {mode:10} {run['status']}")


if __name__ == "__main__":
    main()
