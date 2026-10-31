import Foundation

struct ScenarioService {
    let api: APIClient
    init(api: APIClient = APIClient()) { self.api = api }

    func list() async throws -> [ScenarioSummary] { try await api.get("/api/v1/scenarios") }
    func detail(id: String) async throws -> ScenarioDetail { try await api.get("/api/v1/scenarios/\(id)") }
}
