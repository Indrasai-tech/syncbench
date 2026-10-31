import Foundation

@MainActor
final class RunViewModel: ObservableObject {
    @Published private(set) var run: TestRun?
    @Published private(set) var events: [TestEvent] = []
    @Published private(set) var report: TestReport?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    let runID: String
    private let service: RunService

    init(runID: String, service: RunService = RunService()) {
        self.runID = runID
        self.service = service
    }

    /// Loads the run, polls until it finishes, then loads events and the report.
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var current = try await service.run(id: runID)
            run = current
            var polls = 0
            while !current.isFinished && polls < 40 {
                try await Task.sleep(nanoseconds: 500_000_000)
                current = try await service.run(id: runID)
                run = current
                polls += 1
            }
            if current.status == "passed" || current.status == "failed" {
                async let e = service.events(runID: runID)
                async let r = service.report(runID: runID)
                events = try await e
                report = try await r
            } else if current.status == "error" {
                errorMessage = current.error ?? "The run failed to execute."
            }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() async {
        do { run = try await service.cancel(runID: runID) }
        catch { errorMessage = error.localizedDescription }
    }

    func markdown() async -> String? {
        do { return try await service.reportMarkdown(runID: runID) }
        catch { errorMessage = error.localizedDescription; return nil }
    }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[TestRun]> = .idle
    private let service: RunService

    init(service: RunService = RunService()) { self.service = service }

    func load() async {
        if case .loaded = state {} else { state = .loading }
        do { state = .loaded(try await service.list(limit: 100)) }
        catch is CancellationError {}
        catch { state = .failed(error.localizedDescription) }
    }
}
