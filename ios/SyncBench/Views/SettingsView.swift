import SwiftUI

struct SettingsView: View {
    @State private var baseURL = LocalStore.shared.baseURL
    @State private var apiKey = LocalStore.shared.apiKey
    @State private var result: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    TextField("http://127.0.0.1:8000", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("API key (optional)", text: $apiKey)
                    Text("For iOS Simulator or a physical iPhone, use your Mac's LAN IP with port 8000 (for example, http://192.168.1.10:8000). Do not use 127.0.0.1; that points to the device itself. Find your Mac IP with `ipconfig getifaddr en0`.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack { if isTesting { ProgressView() }; Text("Save & test connection") }
                    }
                    .disabled(isTesting)
                    if let result { Text(result).font(.callout) }
                    Button("Reset to defaults", role: .destructive) {
                        LocalStore.shared.resetConnection()
                        baseURL = LocalStore.shared.baseURL
                        apiKey = ""
                        result = nil
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func testConnection() async {
        LocalStore.shared.baseURL = baseURL
        LocalStore.shared.apiKey = apiKey
        isTesting = true
        defer { isTesting = false }
        do {
            let health = try await RunService().health()
            result = "Connected. Server status: \(health.status), \(health.scenarios ?? 0) scenarios loaded."
        } catch {
            result = error.localizedDescription
        }
    }
}
