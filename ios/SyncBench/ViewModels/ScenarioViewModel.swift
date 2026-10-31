import Foundation

@MainActor
final class ScenarioViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[ScenarioSummary]> = .idle
    private let service: ScenarioService

    init(service: ScenarioService = ScenarioService()) { self.service = service }

    func load() async {
        if case .loaded = state {} else { state = .loading }
        do { state = .loaded(try await service.list()) }
        catch is CancellationError {}
        catch { state = .failed(error.localizedDescription) }
    }
}

@MainActor
final class ScenarioDetailViewModel: ObservableObject {
    @Published private(set) var state: LoadState<ScenarioDetail> = .idle
    @Published var choice: SynchronizerChoice = .scenarioDefault
    @Published private(set) var isStarting = false
    @Published var startError: String?
    @Published var startedRunID: String?

    let scenarioID: String
    private let scenarios: ScenarioService
    private let runs: RunService

    init(scenarioID: String, scenarios: ScenarioService = ScenarioService(), runs: RunService = RunService()) {
        self.scenarioID = scenarioID
        self.scenarios = scenarios
        self.runs = runs
    }

    func load() async {
        state = .loading
        do { state = .loaded(try await scenarios.detail(id: scenarioID)) }
        catch is CancellationError {}
        catch { state = .failed(error.localizedDescription) }
    }

    func startRun() async {
        isStarting = true
        startError = nil
        defer { isStarting = false }
        do {
            let run = try await runs.create(scenarioID: scenarioID, synchronizer: choice.apiValue)
            startedRunID = run.id
        } catch {
            startError = error.localizedDescription
        }
    }
}
