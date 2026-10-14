import Foundation

/// Minimal JSON value for Messages API bodies and the conversation history.
/// Sendable, so history and tool inputs can cross actors.
enum JSON: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    subscript(key: String) -> JSON? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var int: Int? {
        if case .number(let value) = self { return Int(exactly: value) }
        return nil
    }

    static func parse(_ data: Data) throws -> JSON {
        JSON(any: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    func data() throws -> Data {
        try JSONSerialization.data(withJSONObject: any, options: [.sortedKeys, .fragmentsAllowed])
    }

    init(any value: Any) {
        switch value {
        case let number as NSNumber:
            // JSONSerialization returns booleans as NSNumber too.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map(JSON.init(any:)))
        case let object as [String: Any]:
            self = .object(object.mapValues(JSON.init(any:)))
        default:
            self = .null
        }
    }

    var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map(\.any)
        case .object(let value): return value.mapValues(\.any)
        }
    }
}

extension JSON: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self = .string(value)
    }
}
