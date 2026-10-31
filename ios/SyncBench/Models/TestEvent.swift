import Foundation

struct TestEvent: Codable, Identifiable, Hashable {
    var id: Int { seq }
    let seq: Int
    let tMs: Int
    let actor: String
    let type: String
    let detail: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case seq, actor, type, detail
        case tMs = "t_ms"
    }

    var detailText: String { detail.displayLines.joined(separator: "  ") }
}
