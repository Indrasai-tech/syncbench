import Foundation
import Vapor

struct RunCreate: Content { let scenarioId: String; var synchronizer: String?; var seed: Int?; enum CodingKeys: String, CodingKey { case synchronizer, seed; case scenarioId = "scenario_id" } }
struct CompareCreate: Content { let scenarioId: String; var seed: Int?; enum CodingKeys: String, CodingKey { case seed; case scenarioId = "scenario_id" } }
struct Health: Content { let status: String; let service: String; let scenarios: Int }
struct ErrorBody: Content { let detail: String }
extension RunRecord: Content {}
extension RunReport: Content {}
extension RunEvent: Content {}
extension Scenario: Content {}
extension JSONValue: Content {}
struct ValidationResponse: Content { let valid: Bool; let operationCount: Int; let failureCount: Int; let warnings: [String]; enum CodingKeys: String, CodingKey { case valid, warnings; case operationCount = "operation_count"; case failureCount = "failure_count" } }
struct ScenarioSummaryResponse: Content {
    let id, name, description, policy, synchronizer: String
    let operationCount, failureCount: Int
    let assertions: [String]
    enum CodingKeys: String, CodingKey { case id, name, description, policy, synchronizer, assertions; case operationCount = "operation_count"; case failureCount = "failure_count" }
}
struct StatsResponse: Content {
    let totalRuns, passed, failed, errors: Int
    let lostUpdatesDetected, duplicateEffectsDetected, totalRetries: Int
    let avgWallMs: Double
    enum CodingKeys: String, CodingKey {
        case passed, failed, errors
        case totalRuns = "total_runs", lostUpdatesDetected = "lost_updates_detected"
        case duplicateEffectsDetected = "duplicate_effects_detected", totalRetries = "total_retries", avgWallMs = "avg_wall_ms"
    }
}

struct APIKeyMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let configured = Environment.get("API_KEY") ?? ""
        if !configured.isEmpty && request.headers.first(name: "X-API-Key") != configured {
            throw Abort(.unauthorized, reason: "A valid X-API-Key header is required")
        }
        return try await next.respond(to: request)
    }
}

struct DetailErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        do { return try await next.respond(to: request) }
        catch {
            let abort = error as? AbortError
            let isBadBody = error is DecodingError
            let response = Response(status: abort?.status ?? (isBadBody ? .unprocessableEntity : .internalServerError))
            let detail = abort?.reason ?? (isBadBody ? "Request body is invalid" : error.localizedDescription)
            try response.content.encode(ErrorBody(detail: detail))
            return response
        }
    }
}

func configure(_ app: Application) throws {
    app.logger.notice("SyncBench Swift API starting")
    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = Int(Environment.get("PORT") ?? "8000") ?? 8000
    app.middleware.use(DetailErrorMiddleware())
    _ = try ScenarioCatalog.load() // Validate the complete catalogue before accepting requests.
    app.get("health") { _ async throws -> Health in Health(status: "ok", service: "syncbench", scenarios: try ScenarioCatalog.load().count) }

    let api = app.grouped("api").grouped("v1").grouped(APIKeyMiddleware())
    api.get("scenarios") { _ async throws -> [ScenarioSummaryResponse] in
        try ScenarioCatalog.load().values.sorted { $0.id < $1.id }.map { s in
            ScenarioSummaryResponse(id: s.id, name: s.name, description: s.description, policy: s.policy, synchronizer: s.synchronizer,
                                    operationCount: s.operations.count, failureCount: s.failures.count, assertions: s.assertions)
        }
    }
    api.get("scenarios", ":scenarioID") { req async throws -> Scenario in
        let catalog = try ScenarioCatalog.load(); guard let scenario = catalog[req.parameters.get("scenarioID") ?? ""] else { throw Abort(.notFound, reason: "Scenario not found") }; return scenario
    }
    api.post("scenarios", "validate") { req async throws -> ValidationResponse in
        let scenario = try req.content.decode(Scenario.self)
        try scenario.validate()
        let warnings = scenario.failures.isEmpty ? ["Scenario has no injected network faults."] : []
        return ValidationResponse(valid: true, operationCount: scenario.operations.count, failureCount: scenario.failures.count, warnings: warnings)
    }

    api.post("runs") { req async throws -> Response in
        let body = try req.content.decode(RunCreate.self)
        guard let scenario = try ScenarioCatalog.load()[body.scenarioId] else { throw Abort(.notFound, reason: "Scenario '\(body.scenarioId)' not found") }
        let mode = body.synchronizer ?? scenario.synchronizer
        guard ["reference", "naive"].contains(mode) else { throw Abort(.unprocessableEntity, reason: "Unsupported synchronizer '\(mode)'" ) }
        let record = RunRecord(id: UUID().uuidString.lowercased(), scenarioId: scenario.id, synchronizer: mode, seed: body.seed ?? scenario.seed,
                               status: "queued", createdAt: Date(), finishedAt: nil, durationMs: nil, summary: nil, error: nil, report: nil)
        RunStore.shared.insert(record)
        let id = record.id
        Task.detached { await executeRun(id: id, scenario: scenario, mode: mode, seed: record.seed) }
        let response = Response(status: .accepted); try response.content.encode(record); return response
    }
    api.post("runs", "compare") { req async throws -> [String: JSONValue] in
        let body = try req.content.decode(CompareCreate.self)
        guard let scenario = try ScenarioCatalog.load()[body.scenarioId] else { throw Abort(.notFound, reason: "Scenario '\(body.scenarioId)' not found") }
        var referenceRunner = ScenarioRunner(scenario: scenario, synchronizer: "reference", seed: body.seed)
        var naiveRunner = ScenarioRunner(scenario: scenario, synchronizer: "naive", seed: body.seed)
        let reference = referenceRunner.run()
        let naive = naiveRunner.run()
        let firstDifference = zip(reference.events, naive.events).first { $0.0 != $0.1 }
        let divergence: JSONValue = firstDifference.map { pair in
            .object(["seq": .number(Double(pair.0.seq)), "reference_type": .string(pair.0.type), "naive_type": .string(pair.1.type),
                     "reference_actor": .string(pair.0.actor), "naive_actor": .string(pair.1.actor)])
        } ?? .null
        return ["scenario_id": .string(scenario.id), "reference": try JSONValue.from(reference), "naive": try JSONValue.from(naive),
                "same_fingerprint": .bool(reference.fingerprint == naive.fingerprint), "reference_passed": .bool(reference.status == "passed"),
                "naive_passed": .bool(naive.status == "passed"), "first_event_divergence": divergence]
    }
    api.get("runs", "export.csv") { _ async throws -> Response in
        let rows = RunStore.shared.all().sorted { $0.createdAt > $1.createdAt }
        var csv = "id,scenario_id,synchronizer,seed,status,created_at,finished_at,duration_ms,fingerprint\n"
        for run in rows {
            let fields = csvFields(for: run)
            let escaped = fields.map(csvEscape).joined(separator: ",")
            csv += escaped + "\n"
        }
        let response = Response(status: .ok); response.headers.contentType = .init(type: "text", subType: "csv"); response.body = .init(string: csv); return response
    }
    api.get("runs") { req async throws -> [RunRecord] in
        let limit = min(max((try? req.query.get(Int.self, at: "limit")) ?? 50, 1), 200)
        let offset = max((try? req.query.get(Int.self, at: "offset")) ?? 0, 0)
        let scenarioID = try? req.query.get(String.self, at: "scenario_id")
        let status = try? req.query.get(String.self, at: "status")
        return RunStore.shared.list(limit: limit, offset: offset, scenarioID: scenarioID, status: status)
    }
    api.get("runs", ":runID", "events") { req async throws -> [RunEvent] in
        let run = try getRun(req); guard let report = run.report else { return [] }
        let after = max((try? req.query.get(Int.self, at: "after_seq")) ?? 0, 0)
        let limit = min(max((try? req.query.get(Int.self, at: "limit")) ?? 200, 1), 1_000)
        return Array(report.events.filter { $0.seq > after }.prefix(limit))
    }
    api.get("runs", ":runID", "report") { req async throws -> Response in
        let run = try getRun(req); guard let report = run.report else { throw Abort(.conflict, reason: "Report not ready (status '\(run.status)')") }
        if (try? req.query.get(String.self, at: "format")) == "markdown" {
            let response = Response(status: .ok); response.headers.contentType = .init(type: "text", subType: "markdown"); response.body = .init(string: report.markdown); return response
        }
        let response = Response(status: .ok); try response.content.encode(report); return response
    }
    api.post("runs", ":runID", "cancel") { req async throws -> RunRecord in
        let run = try getRun(req)
        guard ["queued", "running"].contains(run.status) else { throw Abort(.conflict, reason: "Run already finished with status '\(run.status)' ") }
        RunStore.shared.update(run.id) { $0.status = "cancelled"; $0.finishedAt = Date() }
        return RunStore.shared.get(run.id) ?? run
    }
    api.post("runs", ":runID", "replay") { req async throws -> Response in
        let original = try getRun(req)
        guard let scenario = try ScenarioCatalog.load()[original.scenarioId] else { throw Abort(.notFound, reason: "Scenario '\(original.scenarioId)' is no longer available") }
        let replay = RunRecord(id: UUID().uuidString.lowercased(), scenarioId: original.scenarioId, synchronizer: original.synchronizer,
                               seed: original.seed, status: "queued", createdAt: Date(), finishedAt: nil, durationMs: nil,
                               summary: nil, error: nil, report: nil)
        RunStore.shared.insert(replay)
        Task.detached { await executeRun(id: replay.id, scenario: scenario, mode: replay.synchronizer, seed: replay.seed) }
        let response = Response(status: .accepted); try response.content.encode(replay); return response
    }
    api.get("runs", ":runID") { req async throws -> RunRecord in try getRun(req) }
    api.get("stats") { _ async throws -> StatsResponse in
        let all = RunStore.shared.all(); let done = all.filter { ["passed", "failed"].contains($0.status) }
        return StatsResponse(totalRuns: all.count, passed: all.filter { $0.status == "passed" }.count,
                             failed: all.filter { $0.status == "failed" }.count, errors: all.filter { $0.status == "error" }.count,
                             lostUpdatesDetected: all.reduce(0) { $0 + ($1.summary?.lostUpdates ?? 0) },
                             duplicateEffectsDetected: all.reduce(0) { $0 + ($1.summary?.duplicateEffects ?? 0) },
                             totalRetries: all.reduce(0) { $0 + ($1.summary?.retries ?? 0) },
                             avgWallMs: done.isEmpty ? 0 : done.reduce(0) { $0 + ($1.durationMs ?? 0) } / Double(done.count))
    }
}

private func getRun(_ req: Request) throws -> RunRecord {
    let id = req.parameters.get("runID") ?? ""; guard let run = RunStore.shared.get(id) else { throw Abort(.notFound, reason: "Run '\(id)' not found") }; return run
}
private func executeRun(id: String, scenario: Scenario, mode: String, seed: Int) async {
    RunStore.shared.update(id) { if $0.status == "queued" { $0.status = "running" } }
    guard RunStore.shared.get(id)?.status == "running" else { return }
    let start = Date()
    var runner = ScenarioRunner(scenario: scenario, synchronizer: mode, seed: seed)
    let report = runner.run { RunStore.shared.get(id)?.status == "cancelled" }
    RunStore.shared.update(id) { record in
        guard record.status != "cancelled" else { return }
        record.status = report.status; record.report = report; record.finishedAt = Date()
        record.durationMs = Date().timeIntervalSince(start) * 1_000
        record.summary = report.metrics
    }
}
private func csvEscape(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
private func csvFields(for run: RunRecord) -> [String] {
    let formatter = ISO8601DateFormatter()
    let created = formatter.string(from: run.createdAt)
    let finished = run.finishedAt.map { formatter.string(from: $0) } ?? ""
    let duration = run.durationMs.map { String($0) } ?? ""
    let fingerprint = run.summary?.fingerprint ?? ""
    return [run.id, run.scenarioId, run.synchronizer, String(run.seed), run.status, created, finished, duration, fingerprint]
}

extension JSONValue {
    static func from<T: Encodable>(_ value: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder.sorted.encode(value)) }
}
extension RunReport {
    var markdown: String {
        var lines = ["# SyncBench report: \(scenarioName)", "", "- **Result:** \(status.uppercased())", "- **Synchronizer:** \(synchronizer) · **Policy:** \(policy) · **Seed:** \(seed)", "- **Fingerprint:** `\(fingerprint)`", "", "## Assertions", "", "| Assertion | Result | Detail |", "|---|---|---|"]
        lines += assertions.map { "| \($0.name) | \($0.passed ? "PASS" : "FAIL") | \($0.message.replacingOccurrences(of: "|", with: "\\|")) |" }
        lines += ["", "## Expected and actual", "", "- Expected: `\(JSONValue.object(expectedFinalState))`", "- Server state: `\(JSONValue.object(finalServerState))`", "", "## Event timeline", ""]
        let flagged = Set(assertions.filter { !$0.passed }.flatMap(\.eventSeqs))
        lines += events.map { "\($0.seq). `t=\($0.tMs)ms` \($0.actor): \($0.type) `\(JSONValue.object($0.detail))`\(flagged.contains($0.seq) ? " **← related to failed assertion**" : "")" }
        return lines.joined(separator: "\n") + "\n"
    }
}
