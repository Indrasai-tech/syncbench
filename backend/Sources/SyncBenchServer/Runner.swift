import Crypto
import Foundation

private struct PendingOp: Sendable { let id: String; let client: String; let kind: String; let field: String; let value: JSONValue; let base: Int }
private struct Effect: Sendable { let id: String; let client: String; let kind: String; let field: String; let value: JSONValue }
private struct ClientState: Sendable {
    let id: String
    var local: [String: JSONValue]
    var versions: [String: Int]
    var pending: [PendingOp] = []
    var online = true
    var counter = 0
}
private struct FaultPlan { var delay = 0; var timeout = false; var unavailable = false; var dropResponse = false; var duplicate = false; var applied: [String] = [] }

struct RunEvent: Codable, Equatable, Sendable {
    let seq, tMs: Int
    let actor, type: String
    let detail: [String: JSONValue]
    enum CodingKeys: String, CodingKey { case seq, actor, type, detail; case tMs = "t_ms" }
}
struct Assertion: Codable, Equatable, Sendable {
    let name: String; let passed: Bool; let expected: JSONValue; let actual: JSONValue; let message: String; let eventSeqs: [Int]
    enum CodingKeys: String, CodingKey { case name, passed, expected, actual, message; case eventSeqs = "event_seqs" }
}
struct RunMetrics: Codable, Sendable {
    let events, retries, lostUpdates, duplicateEffects: Int
    let assertionsTotal, assertionsFailed, simulatedDurationMs: Int
    let wallMs: Double
    var fingerprint: String? = nil
    enum CodingKeys: String, CodingKey {
        case events, retries, fingerprint
        case lostUpdates = "lost_updates", duplicateEffects = "duplicate_effects"
        case assertionsTotal = "assertions_total", assertionsFailed = "assertions_failed"
        case simulatedDurationMs = "simulated_duration_ms", wallMs = "wall_ms"
    }
}
struct RunReport: Codable, Sendable {
    let scenarioId, scenarioName, synchronizer, policy: String
    let seed: Int; let status: String; let assertions: [Assertion]
    let expectedFinalState, finalServerState: [String: JSONValue]
    let metrics: RunMetrics; let fingerprint: String; let events: [RunEvent]
    enum CodingKeys: String, CodingKey {
        case synchronizer, policy, seed, status, assertions, metrics, fingerprint, events
        case scenarioId = "scenario_id", scenarioName = "scenario_name", expectedFinalState = "expected_final_state", finalServerState = "final_server_state"
    }
}

struct ScenarioRunner {
    let scenario: Scenario
    let mode: String
    let seed: Int
    private(set) var clock = 0
    private(set) var events: [RunEvent] = []
    private var state: [String: JSONValue]
    private var versions: [String: Int]
    private var effects: [Effect] = []
    private var clients: [String: ClientState] = [:]
    private var syncCounts: [String: Int] = [:]
    private var seen: Set<String> = []
    private var serverSequence = 0
    private var retries = 0
    private var randomState: UInt64

    init(scenario: Scenario, synchronizer: String? = nil, seed: Int? = nil) {
        self.scenario = scenario; self.mode = synchronizer ?? scenario.synchronizer
        self.seed = seed ?? scenario.seed; self.state = scenario.initialState
        self.versions = Dictionary(uniqueKeysWithValues: scenario.initialState.keys.map { ($0, 1) })
        self.randomState = UInt64(bitPattern: Int64(seed ?? scenario.seed)) &+ 0x9E3779B97F4A7C15
    }

    mutating func run(isCancelled: () -> Bool = { false }) -> RunReport {
        let start = Date()
        log("runner", "run_started", ["scenario": .string(scenario.id), "synchronizer": .string(mode), "policy": .string(scenario.policy), "seed": .number(Double(seed))])
        for op in scenario.operations {
            if isCancelled() { log("runner", "run_cancelled", [:]); break }
            step(op)
        }
        let assertions = evaluate()
        let cancelled = isCancelled()
        let passed = assertions.allSatisfy(\.passed)
        log("runner", "run_finished", ["passed": .bool(passed)])
        let data = (try? JSONEncoder.sorted.encode(events)) ?? Data()
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(16).description
        let lost = lostUpdates().count
        let duplicates = duplicateEffects().count
        let wall = Date().timeIntervalSince(start) * 1_000
        return RunReport(scenarioId: scenario.id, scenarioName: scenario.name, synchronizer: mode, policy: scenario.policy, seed: seed,
            status: cancelled ? "cancelled" : (passed ? "passed" : "failed"), assertions: assertions,
            expectedFinalState: scenario.expectedFinalState, finalServerState: state,
            metrics: RunMetrics(events: events.count, retries: retries, lostUpdates: lost, duplicateEffects: duplicates,
                                assertionsTotal: assertions.count, assertionsFailed: assertions.filter { !$0.passed }.count,
                                simulatedDurationMs: clock, wallMs: wall, fingerprint: fingerprint),
            fingerprint: fingerprint, events: events)
    }

    private mutating func log(_ actor: String, _ type: String, _ detail: [String: JSONValue]) { events.append(RunEvent(seq: events.count + 1, tMs: clock, actor: actor, type: type, detail: detail)) }
    private mutating func client(_ id: String) -> ClientState {
        clients[id] ?? ClientState(id: id, local: scenario.initialState, versions: versions)
    }
    private mutating func step(_ op: Operation) {
        if op.action == "server_update", let field = op.field, let value = op.value {
            serverSequence += 1; let id = "server-\(serverSequence)"; state[field] = value; versions[field, default: 0] += 1
            effects.append(Effect(id: id, client: "server", kind: "update", field: field, value: value))
            log("server", "server_update", ["op_id": .string(id), "field": .string(field), "value": value]); return
        }
        var c = client(op.client)
        if let connection = op.connection { setOnline(&c, connection == "online") }
        switch op.action {
        case "go_offline": setOnline(&c, false)
        case "go_online": setOnline(&c, true)
        case "update", "increment":
            guard let field = op.field, let value = op.value else { clients[c.id] = c; return }
            c.counter += 1; let id = "\(c.id)-\(c.counter)"
            let pending = PendingOp(id: id, client: c.id, kind: op.action, field: field, value: value, base: c.versions[field, default: 1])
            if op.action == "increment", let a = c.local[field]?.numericValue, let b = value.numericValue { c.local[field] = .number(a + b) } else { c.local[field] = value }
            c.pending.append(pending)
            log(c.id, "local_edit", ["op_id": .string(id), "field": .string(field), "value": value, "kind": .string(op.action), "offline": .bool(!c.online), "queued": .number(Double(c.pending.count))])
        case "sync": sync(&c)
        default: break
        }
        clients[c.id] = c
    }
    private mutating func setOnline(_ c: inout ClientState, _ value: Bool) { if c.online != value { c.online = value; log(c.id, value ? "connection_online" : "connection_offline", [:]) } }

    private mutating func sync(_ c: inout ClientState) {
        guard c.online else { log(c.id, "sync_skipped_offline", ["queued": .number(Double(c.pending.count))]); return }
        syncCounts[c.id, default: 0] += 1; let syncNo = syncCounts[c.id]!
        for attempt in 1...(scenario.maxRetries + 1) {
            let plan = makePlan(client: c.id, sync: syncNo, attempt: attempt)
            let ops = c.pending
            log(c.id, "sync_attempt", ["attempt": .number(Double(attempt)), "op_ids": .array(ops.map { .string($0.id) }), "injected": .array(plan.applied.map(JSONValue.string))])
            if plan.delay > 0 { clock += plan.delay; log("network", "delay", ["ms": .number(Double(plan.delay))]) }
            var failed = false
            if plan.timeout { clock += scenario.timeoutMs; log("network", "request_lost", ["reason": .string("timeout")]); failed = true }
            else if plan.unavailable { clock += 50; log("server", "server_unavailable", ["status": .number(503)]); failed = true }
            else {
                let results = receive(ops, local: c.local); logResults(results)
                if plan.duplicate { _ = receive(ops, local: c.local); log("network", "duplicate_delivered", ["op_ids": .array(ops.map { .string($0.id) })]) }
                if plan.dropResponse { clock += scenario.timeoutMs; log("network", "response_lost", ["reason": .string("timeout")]); failed = true }
                else {
                    let acked = Set(results.map { $0.0 }); c.pending.removeAll { acked.contains($0.id) }
                    let pendingFields = Set(c.pending.map(\.field))
                    for (key, value) in state where !pendingFields.contains(key) { c.local[key] = value }
                    if mode == "reference" { c.versions = versions }
                    log(c.id, "sync_complete", ["attempt": .number(Double(attempt)), "pending": .number(Double(c.pending.count))]); return
                }
            }
            if failed && attempt <= scenario.maxRetries { retries += 1; let delay = 100 * (1 << (attempt - 1)); clock += delay; log(c.id, "retry_scheduled", ["next_attempt": .number(Double(attempt + 1)), "backoff_ms": .number(Double(delay))]) }
        }
        log(c.id, "sync_failed", ["reason": .string("retries_exhausted"), "pending": .number(Double(c.pending.count))])
    }

    private mutating func receive(_ ops: [PendingOp], local: [String: JSONValue]) -> [(String, String, String)] {
        var results: [(String, String, String)] = []
        for op in ops {
            if mode == "reference", seen.contains(op.id) { results.append((op.id, op.field, "duplicate_ignored")); continue }
            var status = "applied"
            if mode == "naive" {
                if op.kind == "increment", let a = state[op.field]?.numericValue, let b = op.value.numericValue { state[op.field] = .number(a + b) }
                else { state = local }
            } else if op.kind == "increment", let a = state[op.field]?.numericValue, let b = op.value.numericValue { state[op.field] = .number(a + b); versions[op.field, default: 0] += 1 }
            else if op.base < versions[op.field, default: 0] && scenario.policy != "last_write_wins" { status = "conflict_rejected" }
            else { if op.base < versions[op.field, default: 0] { status = "conflict_resolved_lww" }; state[op.field] = op.value; versions[op.field, default: 0] += 1 }
            if status != "conflict_rejected" { effects.append(Effect(id: op.id, client: op.client, kind: op.kind, field: op.field, value: op.value)) }
            if mode == "reference" { seen.insert(op.id) }
            results.append((op.id, op.field, status))
        }
        return results
    }
    private mutating func logResults(_ results: [(String, String, String)]) { for (id, field, status) in results { log("server", "op_\(status)", ["op_id": .string(id), "field": .string(field)]) } }

    private mutating func makePlan(client: String, sync: Int, attempt: Int) -> FaultPlan {
        var p = FaultPlan()
        for f in scenario.failures where (f.client == "*" || f.client == client) && f.onSync == sync && f.onAttempt == attempt {
            p.applied.append(f.type)
            switch f.type {
            case "delay": p.delay += f.delayMs + (f.jitterMs > 0 ? Int(nextRandom() % UInt64(f.jitterMs + 1)) : 0)
            case "timeout": p.timeout = true
            case "server_unavailable": p.unavailable = true
            case "drop_response": p.dropResponse = true
            case "duplicate_delivery": p.duplicate = true
            default: break
            }
        }
        return p
    }
    private mutating func nextRandom() -> UInt64 { randomState = randomState &* 6364136223846793005 &+ 1442695040888963407; return randomState }
    private func duplicateEffects() -> [String: Int] { var c: [String: Int] = [:]; effects.forEach { c[$0.id, default: 0] += 1 }; return c.filter { $0.value > 1 } }
    private func lostUpdates() -> [Effect] {
        var last: [String: Effect] = [:]; for e in effects where e.kind == "update" { last[e.field] = e }
        return last.values.filter { state[$0.field] != $0.value }
    }

    private func evaluate() -> [Assertion] {
        let dup = duplicateEffects(), lost = lostUpdates()
        func seqs(field: String? = nil, ids: Set<String> = []) -> [Int] {
            events.filter { e in (field != nil && e.detail["field"] == .string(field!)) || (e.detail["op_id"].flatMap { if case .string(let v) = $0 { v } else { nil } }.map(ids.contains) ?? false) }.map(\.seq)
        }
        func result(_ name: String, _ ok: Bool, _ expected: JSONValue, _ actual: JSONValue, _ message: String, _ seq: [Int] = []) -> Assertion { Assertion(name: name, passed: ok, expected: expected, actual: actual, message: message, eventSeqs: ok ? [] : seq) }
        return scenario.assertions.map { name in
            switch name {
            case "no_duplicate_business_effects": return result(name, dup.isEmpty, .string("each operation applied at most once"), dup.isEmpty ? .string("no duplicates") : .object(dup.mapValues { .number(Double($0)) }), dup.isEmpty ? "OK" : "Operations applied more than once", seqs(ids: Set(dup.keys)))
            case "no_lost_updates": return result(name, lost.isEmpty, .string("final value equals last applied update"), .number(Double(lost.count)), lost.isEmpty ? "OK" : "Updates were overwritten after being applied", Array(Set(lost.flatMap { seqs(field: $0.field) })))
            case "all_operations_acknowledged":
                let pending = clients.values.flatMap(\.pending); return result(name, pending.isEmpty, .string("no pending operations"), .number(Double(pending.count)), pending.isEmpty ? "OK" : "Operations never acknowledged", seqs(ids: Set(pending.map(\.id))))
            case "final_state_matches_expected":
                let actual = Dictionary(uniqueKeysWithValues: scenario.expectedFinalState.keys.map { ($0, state[$0] ?? .null) })
                return result(name, actual == scenario.expectedFinalState, .object(scenario.expectedFinalState), .object(actual), actual == scenario.expectedFinalState ? "OK" : "Final server state differs from expected")
            default:
                let field = String(name.dropLast("_matches_expected".count)); let expected = scenario.expectedFinalState[field] ?? .null; let actual = state[field] ?? .null
                return result(name, expected == actual, expected, actual, expected == actual ? "OK" : "\(field) differs from expected", seqs(field: field))
            }
        }
    }
}
