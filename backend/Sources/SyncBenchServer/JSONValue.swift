import Foundation

enum JSONValue: Codable, Equatable, Sendable, CustomStringConvertible {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var description: String {
        switch self {
        case .string(let v): v
        case .number(let v): v.rounded() == v ? String(Int(v)) : String(v)
        case .bool(let v): String(v)
        case .array(let v): "[" + v.map(\.description).joined(separator: ", ") + "]"
        case .object(let v): "{" + v.keys.sorted().map { "\($0): \(v[$0]!)" }.joined(separator: ", ") + "}"
        case .null: "null"
        }
    }

    var numericValue: Double? { if case .number(let n) = self { n } else { nil } }
}

extension Dictionary where Key == String, Value == JSONValue {
    subscript(value key: String) -> JSONValue? { self[key] }
}

extension JSONEncoder {
    static var sorted: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return encoder }
}
