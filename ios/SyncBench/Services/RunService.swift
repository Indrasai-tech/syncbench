import Foundation

private struct CreateRunBody: Encodable {
    let scenarioId: String
    let synchronizer: String?
    enum CodingKeys: String, CodingKey {
        case scenarioId = "scenario_id"
        case synchronizer
    }
}

struct HealthStatus: Decodable {
    let status: String
    let scenarios: Int?
}

struct RunService {
    let api: APIClient
    init(api: APIClient = APIClient()) { self.api = api }

    func health() async throws -> HealthStatus { try await api.get("/health") }
    func stats() async throws -> RunStats { try await api.get("/api/v1/stats") }

    func create(scenarioID: String, synchronizer: String?) async throws -> TestRun {
        try await api.post("/api/v1/runs", body: CreateRunBody(scenarioId: scenarioID, synchronizer: synchronizer))
    }

    func list(limit: Int = 50) async throws -> [TestRun] {
        try await api.get("/api/v1/runs", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func run(id: String) async throws -> TestRun { try await api.get("/api/v1/runs/\(id)") }
    func events(runID: String) async throws -> [TestEvent] { try await api.get("/api/v1/runs/\(runID)/events") }
    func report(runID: String) async throws -> TestReport { try await api.get("/api/v1/runs/\(runID)/report") }

    func reportMarkdown(runID: String) async throws -> String {
        try await api.text("/api/v1/runs/\(runID)/report", query: [URLQueryItem(name: "format", value: "markdown")])
    }

    func cancel(runID: String) async throws -> TestRun { try await api.postEmpty("/api/v1/runs/\(runID)/cancel") }
}
