import Foundation

struct ScenarioSummary: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let policy: String
    let synchronizer: String
    let operationCount: Int
    let failureCount: Int
    let assertions: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, description, policy, synchronizer, assertions
        case operationCount = "operation_count"
        case failureCount = "failure_count"
    }
}

struct ScenarioOperation: Codable, Hashable, Identifiable {
    var id: String { "\(client)-\(action)-\(field ?? "")-\(value?.description ?? "")-\(connection ?? "")" }
    let client: String
    let action: String
    let connection: String?
    let field: String?
    let value: JSONValue?

    var summary: String {
        var parts = [client, action]
        if let field { parts.append(field) }
        if let value, value != .null { parts.append("= \(value)") }
        if let connection { parts.append("(\(connection))") }
        return parts.joined(separator: " ")
    }
}

struct ScenarioFailure: Codable, Hashable, Identifiable {
    var id: String { "\(type)-\(client)-\(onSync)-\(onAttempt)" }
    let type: String
    let client: String
    let onSync: Int
    let onAttempt: Int
    let delayMs: Int
    let jitterMs: Int

    enum CodingKeys: String, CodingKey {
        case type, client
        case onSync = "on_sync"
        case onAttempt = "on_attempt"
        case delayMs = "delay_ms"
        case jitterMs = "jitter_ms"
    }
}

struct ScenarioDetail: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let policy: String
    let synchronizer: String
    let seed: Int
    let maxRetries: Int
    let timeoutMs: Int
    let initialState: [String: JSONValue]
    let operations: [ScenarioOperation]
    let failures: [ScenarioFailure]
    let expectedFinalState: [String: JSONValue]
    let assertions: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, description, policy, synchronizer, seed, operations, failures, assertions
        case maxRetries = "max_retries"
        case timeoutMs = "timeout_ms"
        case initialState = "initial_state"
        case expectedFinalState = "expected_final_state"
    }
}

/// Which synchronizer implementation to test. `scenarioDefault` sends no override.
enum SynchronizerChoice: String, CaseIterable, Identifiable {
    case scenarioDefault, reference, naive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .scenarioDefault: return "Default"
        case .reference: return "Reference"
        case .naive: return "Naive"
        }
    }
    var apiValue: String? { self == .scenarioDefault ? nil : rawValue }
}
