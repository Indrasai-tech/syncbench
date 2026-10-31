import Foundation

struct AssertionResult: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let passed: Bool
    let expected: JSONValue
    let actual: JSONValue
    let message: String
    let eventSeqs: [Int]

    enum CodingKeys: String, CodingKey {
        case name, passed, expected, actual, message
        case eventSeqs = "event_seqs"
    }
}

struct TestReport: Codable, Hashable {
    let scenarioId: String
    let scenarioName: String
    let synchronizer: String
    let policy: String
    let seed: Int
    let status: String
    let assertions: [AssertionResult]
    let expectedFinalState: [String: JSONValue]
    let finalServerState: [String: JSONValue]
    let metrics: RunMetrics
    let fingerprint: String
    let events: [TestEvent]

    enum CodingKeys: String, CodingKey {
        case synchronizer, policy, seed, status, assertions, metrics, fingerprint, events
        case scenarioId = "scenario_id"
        case scenarioName = "scenario_name"
        case expectedFinalState = "expected_final_state"
        case finalServerState = "final_server_state"
    }

    /// Sequence numbers of events that a failed assertion points at.
    var flaggedEventSeqs: Set<Int> {
        Set(assertions.filter { !$0.passed }.flatMap(\.eventSeqs))
    }
}
