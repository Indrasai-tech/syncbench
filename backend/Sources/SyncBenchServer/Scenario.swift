import Foundation

struct Scenario: Codable, Sendable {
    let id, name: String
    var description = ""
    let policy: String
    var synchronizer = "reference"
    var seed = 42
    var maxRetries = 3
    var timeoutMs = 5_000
    let initialState: [String: JSONValue]
    let operations: [Operation]
    var failures: [Failure] = []
    let expectedFinalState: [String: JSONValue]
    let assertions: [String]
    enum CodingKeys: String, CodingKey {
        case id, name, description, policy, synchronizer, seed, operations, failures, assertions
        case maxRetries = "max_retries", timeoutMs = "timeout_ms", initialState = "initial_state", expectedFinalState = "expected_final_state"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        policy = try c.decode(String.self, forKey: .policy); synchronizer = try c.decodeIfPresent(String.self, forKey: .synchronizer) ?? "reference"
        seed = try c.decodeIfPresent(Int.self, forKey: .seed) ?? 42; maxRetries = try c.decodeIfPresent(Int.self, forKey: .maxRetries) ?? 3
        timeoutMs = try c.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 5_000
        initialState = try c.decode([String: JSONValue].self, forKey: .initialState); operations = try c.decode([Operation].self, forKey: .operations)
        failures = try c.decodeIfPresent([Failure].self, forKey: .failures) ?? []
        expectedFinalState = try c.decode([String: JSONValue].self, forKey: .expectedFinalState)
        assertions = try c.decode([String].self, forKey: .assertions)
    }

    func validate() throws {
        guard id.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else { throw BenchError.invalid("scenario id must be lowercase letters, digits and hyphens") }
        guard ["server_wins", "last_write_wins", "merge_non_overlapping_fields"].contains(policy) else { throw BenchError.invalid("unsupported conflict policy: \(policy)") }
        guard ["reference", "naive"].contains(synchronizer), !operations.isEmpty, operations.count <= 200,
              (0...10).contains(maxRetries), (1...60_000).contains(timeoutMs), !assertions.isEmpty else {
            throw BenchError.invalid("scenario must have 1–200 operations, at least one assertion, supported retry limits, and a supported synchronizer")
        }
        for op in operations {
            guard ["update", "increment", "sync", "go_offline", "go_online", "server_update"].contains(op.action) else { throw BenchError.invalid("unknown action: \(op.action)") }
            if let connection = op.connection, !["online", "offline"].contains(connection) { throw BenchError.invalid("connection must be online or offline") }
            if ["update", "increment", "server_update"].contains(op.action) {
                guard let field = op.field, initialState[field] != nil else { throw BenchError.invalid("action \(op.action) requires a field in initial_state") }
            }
            if ["update", "server_update"].contains(op.action), op.value == nil || op.value == .null { throw BenchError.invalid("action \(op.action) requires a non-null value") }
            if op.action == "increment", op.value?.numericValue == nil || initialState[op.field ?? ""]?.numericValue == nil { throw BenchError.invalid("increment requires a numeric value and numeric initial field") }
        }
        for failure in failures {
            guard ["delay", "timeout", "server_unavailable", "drop_response", "duplicate_delivery"].contains(failure.type),
                  failure.onSync >= 1, failure.onAttempt >= 1, (0...60_000).contains(failure.delayMs), (0...60_000).contains(failure.jitterMs) else {
                throw BenchError.invalid("invalid failure rule")
            }
        }
        for failure in failures where failure.client != "*" && !operations.contains(where: { $0.client == failure.client }) { throw BenchError.invalid("failure targets unknown client \(failure.client)") }
        let staticNames = ["no_duplicate_business_effects", "no_lost_updates", "all_operations_acknowledged", "final_state_matches_expected"]
        for name in assertions where !staticNames.contains(name) {
            guard name.hasSuffix("_matches_expected"), expectedFinalState[String(name.dropLast("_matches_expected".count))] != nil else { throw BenchError.invalid("unknown or invalid assertion: \(name)") }
        }
    }
}

struct Operation: Codable, Sendable {
    let client: String
    let action: String
    var connection: String?
    var field: String?
    var value: JSONValue?
}

struct Failure: Codable, Sendable {
    let type: String
    var client = "*"
    var onSync = 1
    var onAttempt = 1
    var delayMs = 0
    var jitterMs = 0
    enum CodingKeys: String, CodingKey { case type, client; case onSync = "on_sync"; case onAttempt = "on_attempt"; case delayMs = "delay_ms"; case jitterMs = "jitter_ms" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type); client = try c.decodeIfPresent(String.self, forKey: .client) ?? "*"
        onSync = try c.decodeIfPresent(Int.self, forKey: .onSync) ?? 1; onAttempt = try c.decodeIfPresent(Int.self, forKey: .onAttempt) ?? 1
        delayMs = try c.decodeIfPresent(Int.self, forKey: .delayMs) ?? 0; jitterMs = try c.decodeIfPresent(Int.self, forKey: .jitterMs) ?? 0
    }
}

enum BenchError: Error, LocalizedError {
    case invalid(String), notFound(String), conflict(String)
    var errorDescription: String? { switch self { case .invalid(let s), .notFound(let s), .conflict(let s): s } }
}

enum ScenarioCatalog {
    static func load() throws -> [String: Scenario] {
        let dir = ProcessInfo.processInfo.environment["SCENARIOS_DIR"] ?? "../scenarios"
        let root = URL(fileURLWithPath: dir, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/")).standardizedFileURL
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result: [String: Scenario] = [:]
        let decoder = JSONDecoder()
        for file in files {
            let scenario = try decoder.decode(Scenario.self, from: Data(contentsOf: file))
            try scenario.validate()
            guard result[scenario.id] == nil else { throw BenchError.invalid("duplicate scenario id \(scenario.id)") }
            result[scenario.id] = scenario
        }
        return result
    }
}
