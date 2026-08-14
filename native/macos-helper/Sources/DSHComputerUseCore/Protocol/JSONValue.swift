import Foundation

/// A lossless, order-preserving representation of an arbitrary JSON value.
///
/// The NDJSON protocol wraps `params` and `result`/`error` payloads in this
/// type so that the request/response envelope can be validated independently of
/// the concrete method-specific models.
public enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// Convenience accessor for an object's keyed payload.
    public var dictionary: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Convenience accessor for an array payload.
    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// Convenience accessor for a string payload.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

/// Bridges typed, `Codable` models to and from `JSONValue` via a JSON round-trip.
/// This keeps method handlers strongly typed while the transport stays generic.
public enum CodableBridge {
    public static func toJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func fromJSONValue<T: Decodable>(_ value: JSONValue) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
