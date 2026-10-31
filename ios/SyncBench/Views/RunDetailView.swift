import SwiftUI

struct RunDetailView: View {
    @StateObject private var vm: RunViewModel

    init(runID: String) {
        _vm = StateObject(wrappedValue: RunViewModel(runID: runID))
    }

    var body: some View {
        List {
            if let run = vm.run {
                Section {
                    HStack {
                        Text(run.scenarioId).font(.headline)
                        Spacer()
                        StatusBadge(status: run.status)
                    }
                    LabeledContent("Synchronizer", value: run.synchronizer)
                    LabeledContent("Seed", value: "\(run.seed)")
                    if !run.isFinished {
                        HStack {
                            ProgressView()
                            Text("Running…")
                            Spacer()
                            Button("Cancel", role: .destructive) { Task { await vm.cancel() } }
                        }
                    }
                }
            } else if vm.isLoading {
                Section { HStack { ProgressView(); Text("Loading run…") } }
            }

            if let message = vm.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red)
                    Button("Retry") { Task { await vm.load() } }
                }
            }

            if let report = vm.report {
                Section("Metrics") {
                    LabeledContent("Lost updates", value: "\(report.metrics.lostUpdates ?? 0)")
                    LabeledContent("Duplicate effects", value: "\(report.metrics.duplicateEffects ?? 0)")
                    LabeledContent("Retries", value: "\(report.metrics.retries ?? 0)")
                    LabeledContent("Simulated time", value: "\(report.metrics.simulatedDurationMs ?? 0) ms")
                    LabeledContent("Fingerprint", value: report.fingerprint)
                }
                Section("Assertions") {
                    ForEach(report.assertions) { a in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(a.name, systemImage: a.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(a.passed ? .green : .red)
                            if !a.passed {
                                Text(a.message).font(.caption)
                                Text("expected: \(a.expected.description)").font(.caption.monospaced())
                                Text("actual: \(a.actual.description)").font(.caption.monospaced())
                            }
                        }
                    }
                }
                Section("Expected vs actual") {
                    ForEach(report.expectedFinalState.keys.sorted(), id: \.self) { key in
                        let expected = report.expectedFinalState[key]?.description ?? "-"
                        let actual = report.finalServerState[key]?.description ?? "-"
                        HStack {
                            Text(key).font(.callout.bold())
                            Spacer()
                            Text(expected).font(.callout.monospaced())
                            Image(systemName: expected == actual ? "equal.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(expected == actual ? .green : .red)
                            Text(actual).font(.callout.monospaced())
                        }
                    }
                }
                Section {
                    NavigationLink("Full report & export") { ReportView(vm: vm) }
                }
            }

            if !vm.events.isEmpty {
                Section("Event timeline") {
                    let flagged = vm.report?.flaggedEventSeqs ?? []
                    ForEach(vm.events) { event in
                        EventRow(event: event, flagged: flagged.contains(event.seq))
                    }
                }
            }
        }
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }
}

struct EventRow: View {
    let event: TestEvent
    let flagged: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("#\(event.seq)").font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(event.type).font(.callout.weight(.semibold))
                Spacer()
                Text("\(event.tMs) ms").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Text(event.actor).font(.caption).foregroundStyle(.secondary)
            if !event.detail.isEmpty {
                Text(event.detailText).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(flagged ? Color.red.opacity(0.12) : nil)
    }
}
