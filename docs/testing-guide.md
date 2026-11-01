# Build and verification guide

## Backend

```bash
cd backend
swift build
swift test
swift run syncbench-server compare
```

The comparison command runs every scenario against both synchronizers. To save its Markdown table:

```bash
swift run syncbench-server compare --write ../docs/comparison-results.md
```

The comparison validates modeled behavior with a virtual clock; it is not a real network benchmark.

## iOS app

The iOS target includes `ModelTests` for JSON decoding and `APIClientTests` for URL building, headers, and error mapping with a mocked URL protocol. Generate the project with XcodeGen, open it in Xcode, and run the **SyncBench** scheme with Cmd+U.

## Scenario review checklist

- Confirm startup validation accepts each new scenario.
- Run the reference and naive implementations with the same scenario seed.
- Check expected pass/fail classification and assertion details.
- Review lost updates, duplicate effects, pending operations, retries, simulated duration, and fingerprint stability.
