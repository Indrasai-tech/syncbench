import Foundation

struct RunRecord: Codable, Sendable {
    let id: String
    let scenarioId: String
    var synchronizer: String
    let seed: Int
    var status: String
    let createdAt: Date
    var finishedAt: Date?
    var durationMs: Double?
    var summary: RunMetrics?
    var error: String?
    var report: RunReport?
    enum CodingKeys: String, CodingKey {
        case id, synchronizer, seed, status, summary, error, report
        case scenarioId = "scenario_id", createdAt = "created_at", finishedAt = "finished_at", durationMs = "duration_ms"
    }
}

final class RunStore: @unchecked Sendable {
    static let shared = RunStore()
    private let lock = NSLock()
    private var records: [String: RunRecord] = [:]
    private let fileURL: URL

    private init() {
        let dir = ProcessInfo.processInfo.environment["DATA_DIR"] ?? "./data"
        let folder = URL(fileURLWithPath: dir, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        fileURL = folder.appendingPathComponent("syncbench-runs.json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL), let loaded = try? decoder.decode([String: RunRecord].self, from: data) { records = loaded }
    }

    func insert(_ run: RunRecord) { lock.lock(); defer { lock.unlock() }; records[run.id] = run; persist() }
    func get(_ id: String) -> RunRecord? { lock.lock(); defer { lock.unlock() }; return records[id] }
    func update(_ id: String, _ change: (inout RunRecord) -> Void) { lock.lock(); defer { lock.unlock() }; guard var run = records[id] else { return }; change(&run); records[id] = run; persist() }
    func list(limit: Int, offset: Int, scenarioID: String? = nil, status: String? = nil) -> [RunRecord] {
        lock.lock(); defer { lock.unlock() }
        let all = records.values.filter { (scenarioID == nil || $0.scenarioId == scenarioID) && (status == nil || $0.status == status) }.sorted { $0.createdAt > $1.createdAt }
        return Array(all.dropFirst(offset).prefix(limit))
    }
    func all() -> [RunRecord] { lock.lock(); defer { lock.unlock() }; return Array(records.values) }
    private func persist() {
        do { try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder.sorted; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(records).write(to: fileURL, options: .atomic)
        } catch { FileHandle.standardError.write(Data("Could not persist SyncBench runs: \(error.localizedDescription)\n".utf8)) }
    }
}
