import SwiftUI

struct ScenarioListView: View {
    @StateObject private var vm = ScenarioViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch vm.state {
                case .idle, .loading:
                    ProgressView("Loading scenarios…")
                case .failed(let message):
                    ErrorStateView(message: message) { Task { await vm.load() } }
                case .loaded(let items) where items.isEmpty:
                    ContentUnavailableView("No scenarios", systemImage: "tray",
                                           description: Text("Add JSON files to the scenarios/ folder."))
                case .loaded(let items):
                    List(items) { item in
                        NavigationLink { ScenarioDetailView(scenarioID: item.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.headline)
                                Text(item.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                Text("\(item.policy) · \(item.operationCount) steps · \(item.failureCount) failures")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("Scenarios")
            .task { await vm.load() }
        }
    }
}
