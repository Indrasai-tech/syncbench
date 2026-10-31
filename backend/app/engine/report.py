from __future__ import annotations

from typing import Any


def report_to_markdown(report: dict[str, Any]) -> str:
    m = report["metrics"]
    lines = [
        f"# SyncBench report: {report['scenario_name']}",
        "",
        f"- **Result:** {report['status'].upper()}",
        f"- **Synchronizer:** {report['synchronizer']}  |  **Policy:** {report['policy']}  |  **Seed:** {report['seed']}",
        f"- **Fingerprint:** `{report['fingerprint']}` (identical for identical settings)",
        f"- **Lost updates:** {m['lost_updates']}  |  **Duplicate effects:** {m['duplicate_effects']}  |  **Retries:** {m['retries']}",
        f"- **Simulated duration:** {m['simulated_duration_ms']} ms",
        "",
        "## Assertions",
        "",
        "| Assertion | Result | Detail |",
        "|---|---|---|",
    ]
    for a in report["assertions"]:
        lines.append(f"| {a['name']} | {'PASS' if a['passed'] else 'FAIL'} | {a['message']} |")
    lines += ["", "## Expected vs actual", "",
              f"- Expected: `{report['expected_final_state']}`",
              f"- Server state: `{report['final_server_state']}`", "", "## Event timeline", ""]
    flagged = {s for a in report["assertions"] for s in a["event_seqs"]}
    for e in report["events"]:
        mark = " **<- related to a failed assertion**" if e["seq"] in flagged else ""
        lines.append(f"{e['seq']}. `t={e['t_ms']}ms` {e['actor']}: {e['type']} {e['detail']}{mark}")
    return "\n".join(lines) + "\n"
