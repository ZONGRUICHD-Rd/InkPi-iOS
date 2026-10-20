import Foundation

/// Lenient JSON tree. The cloud API, the Pi and the hotspot daemon all return
/// loosely typed JSON, and the debug screens show it verbatim, so responses are
/// decoded into this instead of strict models.
enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    init(any: Any?) {
        switch any {
        case nil, is NSNull: self = .null
        case let v as NSNumber:
            if CFGetTypeID(v) == CFBooleanGetTypeID() { self = .bool(v.boolValue) } else { self = .number(v.doubleValue) }
        case let v as String: self = .string(v)
        case let v as [Any]: self = .array(v.map { JSONValue(any: $0) })
        case let v as [String: Any]: self = .object(v.mapValues { JSONValue(any: $0) })
        default: self = .string(String(describing: any!))
        }
    }

    static func parse(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func parse(_ text: String) -> JSONValue? {
        parse(Data(text.utf8))
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var string: String? {
        switch self {
        case .string(let v): return v
        case .number(let v): return v.rounded() == v ? String(Int(v)) : String(v)
        case .bool(let v): return v ? "true" : "false"
        default: return nil
        }
    }

    var double: Double? {
        switch self {
        case .number(let v): return v
        case .string(let v): return Double(v)
        default: return nil
        }
    }

    var int: Int? { double.map { Int($0.rounded()) } }

    var bool: Bool? {
        switch self {
        case .bool(let v): return v
        case .number(let v): return v != 0
        default: return nil
        }
    }

    var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    var isNull: Bool { if case .null = self { return true }; return false }

    var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .number(let v): return v.rounded() == v && abs(v) < 1e15 ? Int(v) as Any : v as Any
        case .string(let v): return v
        case .array(let v): return v.map(\.anyValue)
        case .object(let v): return v.mapValues(\.anyValue)
        }
    }

    /// Pretty-printed JSON (like `JSON.stringify(value, null, 2)` in the web app).
    var pretty: String {
        if case .string(let s) = self { return s }
        let value = anyValue
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8)
        else { return string ?? "null" }
        return text
    }
}

extension Encodable {
    var prettyJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
