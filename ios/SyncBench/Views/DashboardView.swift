import SwiftUI

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch vm.state {
                case .idle, .loading:
                    ProgressView("Loading…")
                case .failed(let message):
                    ErrorStateView(message: message) { Task { await vm.load() } }
                case .loaded(let data):
                    content(data)
                }
            }
            .navigationTitle("SyncBench")
            .task { await vm.load() }
        }
    }

    @ViewBuilder
    private func content(_ data: DashboardData) -> some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatCard(title: "Total runs", value: "\(data.stats.totalRuns)")
                    StatCard(title: "Passed", value: "\(data.stats.passed)", tint: .green)
                    StatCard(title: "Failed", value: "\(data.stats.failed)", tint: .red)
                    StatCard(title: "Lost updates found", value: "\(data.stats.lostUpdatesDetected)")
                    StatCard(title: "Duplicate effects found", value: "\(data.stats.duplicateEffectsDetected)")
                    StatCard(title: "Avg run time", value: String(format: "%.1f ms", data.stats.avgWallMs))
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section("Recent runs") {
                if data.recent.isEmpty {
                    ContentUnavailableView("No runs yet", systemImage: "play.circle",
                                           description: Text("Open the Scenarios tab and run one."))
                } else {
                    ForEach(data.recent) { run in
                        NavigationLink { RunDetailView(runID: run.id) } label: { RunRow(run: run) }
                    }
                }
            }
        }
        .refreshable { await vm.load() }
    }
}
