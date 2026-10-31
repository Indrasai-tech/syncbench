import SwiftUI

struct ScenarioDetailView: View {
    @StateObject private var vm: ScenarioDetailViewModel

    init(scenarioID: String) {
        _vm = StateObject(wrappedValue: ScenarioDetailViewModel(scenarioID: scenarioID))
    }

    var body: some View {
        Group {
            switch vm.state {
            case .idle, .loading:
                ProgressView()
            case .failed(let message):
                ErrorStateView(message: message) { Task { await vm.load() } }
            case .loaded(let scenario):
                content(scenario)
            }
        }
        .navigationTitle("Scenario")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .navigationDestination(item: $vm.startedRunID) { runID in
            RunDetailView(runID: runID)
        }
    }

    @ViewBuilder
    private func content(_ s: ScenarioDetail) -> some View {
        List {
            Section {
                Text(s.name).font(.title3.bold())
                Text(s.description)
                LabeledContent("Conflict policy", value: s.policy)
                LabeledContent("Seed", value: "\(s.seed)")
            }
            Section("Run") {
                Picker("Synchronizer", selection: $vm.choice) {
                    ForEach(SynchronizerChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Default uses \(s.synchronizer). Try Naive to watch SyncBench catch real failures.")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    Task { await vm.startRun() }
                } label: {
                    HStack {
                        if vm.isStarting { ProgressView() }
                        Text(vm.isStarting ? "Starting…" : "Run scenario")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isStarting)
                if let error = vm.startError {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("Retry") { Task { await vm.startRun() } }
                }
            }
            Section("Initial state") {
                ForEach(s.initialState.displayLines, id: \.self) { Text($0).font(.callout.monospaced()) }
            }
            Section("Operations") {
                ForEach(Array(s.operations.enumerated()), id: \.offset) { index, op in
                    Text("\(index + 1). \(op.summary)").font(.callout.monospaced())
                }
            }
            if !s.failures.isEmpty {
                Section("Injected failures") {
                    ForEach(s.failures) { f in
                        Text("\(f.type) on \(f.client), sync #\(f.onSync), attempt #\(f.onAttempt)")
                            .font(.callout)
                    }
                }
            }
            Section("Expected final state") {
                ForEach(s.expectedFinalState.displayLines, id: \.self) { Text($0).font(.callout.monospaced()) }
            }
            Section("Assertions") {
                ForEach(s.assertions, id: \.self) { Text($0).font(.callout) }
            }
        }
    }
}
