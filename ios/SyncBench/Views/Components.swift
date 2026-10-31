import SwiftUI

extension String {
    var statusColor: Color {
        switch self {
        case "passed": return .green
        case "failed", "error": return .red
        case "running", "queued": return .orange
        default: return .gray
        }
    }
}

struct StatusBadge: View {
    let status: String
    var body: some View {
        Text(status.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.statusColor.opacity(0.18), in: Capsule())
            .foregroundStyle(status.statusColor)
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry", action: retry).buttonStyle(.borderedProminent)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var tint: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.bold()).foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct RunRow: View {
    let run: TestRun
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(run.scenarioId).font(.headline)
                Spacer()
                StatusBadge(status: run.status)
            }
            HStack(spacing: 8) {
                Text(run.synchronizer)
                if let lost = run.summary?.lostUpdates, lost > 0 { Text("lost: \(lost)") }
                if let dup = run.summary?.duplicateEffects, dup > 0 { Text("duplicates: \(dup)") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
