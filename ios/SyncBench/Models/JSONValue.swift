import Foundation

/// Arbitrary JSON (scenario values, event details, expected/actual state).
enum JSONValue: Codable, Hashable, CustomStringConvertible {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let n = try? c.decode(Double.self) { self = .number(n) }   // before Bool: keeps 0/1 numeric
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
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
        case .string(let s): return s
        case .number(let n): return (n == n.rounded() && abs(n) < 1e15) ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let a): return "[" + a.map(\.description).joined(separator: ", ") + "]"
        case .object(let o):
            return "{" + o.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ") + "}"
        }
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    /// "key: value" lines sorted by key, for display.
    var displayLines: [String] {
        sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
    }
}
