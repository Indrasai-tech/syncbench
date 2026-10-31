import SwiftUI

struct ReportView: View {
    @ObservedObject var vm: RunViewModel
    @State private var markdown: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            if let markdown {
                Text(markdown)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else if isLoading {
                ProgressView().padding()
            } else if let message = vm.errorMessage {
                ErrorStateView(message: message) { Task { await load() } }
            }
        }
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let markdown {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: markdown, subject: Text("SyncBench report"))
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        markdown = await vm.markdown()
        isLoading = false
    }
}
