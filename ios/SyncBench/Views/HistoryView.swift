import SwiftUI

struct HistoryView: View {
    @StateObject private var vm = HistoryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch vm.state {
                case .idle, .loading:
                    ProgressView("Loading history…")
                case .failed(let message):
                    ErrorStateView(message: message) { Task { await vm.load() } }
                case .loaded(let runs) where runs.isEmpty:
                    ContentUnavailableView("No test history", systemImage: "clock",
                                           description: Text("Runs you start will appear here."))
                case .loaded(let runs):
                    List(runs) { run in
                        NavigationLink { RunDetailView(runID: run.id) } label: { RunRow(run: run) }
                    }
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("History")
            .task { await vm.load() }
        }
    }
}
