import Foundation

/// Small UserDefaults-backed store for connection settings. The API address lives here, never hardcoded in views.
final class LocalStore: @unchecked Sendable {
    static let shared = LocalStore()
    static let defaultBaseURL = "http://127.0.0.1:8000"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var baseURL: String {
        get { defaults.string(forKey: "syncbench.baseURL") ?? Self.defaultBaseURL }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "syncbench.baseURL") }
    }

    var apiKey: String {
        get { defaults.string(forKey: "syncbench.apiKey") ?? "" }
        set { defaults.set(newValue, forKey: "syncbench.apiKey") }
    }

    func resetConnection() {
        defaults.removeObject(forKey: "syncbench.baseURL")
        defaults.removeObject(forKey: "syncbench.apiKey")
    }
}
