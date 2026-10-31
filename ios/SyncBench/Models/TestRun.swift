import Foundation

struct RunMetrics: Codable, Hashable {
    let events: Int?
    let retries: Int?
    let lostUpdates: Int?
    let duplicateEffects: Int?
    let assertionsTotal: Int?
    let assertionsFailed: Int?
    let simulatedDurationMs: Int?
    let wallMs: Double?
    let fingerprint: String?

    enum CodingKeys: String, CodingKey {
        case events, retries, fingerprint
        case lostUpdates = "lost_updates"
        case duplicateEffects = "duplicate_effects"
        case assertionsTotal = "assertions_total"
        case assertionsFailed = "assertions_failed"
        case simulatedDurationMs = "simulated_duration_ms"
        case wallMs = "wall_ms"
    }
}

struct TestRun: Codable, Identifiable, Hashable {
    let id: String
    let scenarioId: String
    let synchronizer: String
    let seed: Int
    let status: String
    let createdAt: String?
    let finishedAt: String?
    let durationMs: Double?
    let summary: RunMetrics?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id, synchronizer, seed, status, summary, error
        case scenarioId = "scenario_id"
        case createdAt = "created_at"
        case finishedAt = "finished_at"
        case durationMs = "duration_ms"
    }

    var isFinished: Bool { !["queued", "running"].contains(status) }
}

struct RunStats: Codable, Hashable {
    let totalRuns: Int
    let passed: Int
    let failed: Int
    let errors: Int
    let lostUpdatesDetected: Int
    let duplicateEffectsDetected: Int
    let totalRetries: Int
    let avgWallMs: Double

    enum CodingKeys: String, CodingKey {
        case passed, failed, errors
        case totalRuns = "total_runs"
        case lostUpdatesDetected = "lost_updates_detected"
        case duplicateEffectsDetected = "duplicate_effects_detected"
        case totalRetries = "total_retries"
        case avgWallMs = "avg_wall_ms"
    }
}
