import Foundation

struct DashboardData {
    let stats: RunStats
    let recent: [TestRun]
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var state: LoadState<DashboardData> = .idle
    private let service: RunService

    init(service: RunService = RunService()) { self.service = service }

    func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            async let stats = service.stats()
            async let recent = service.list(limit: 8)
            state = .loaded(DashboardData(stats: try await stats, recent: try await recent))
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
