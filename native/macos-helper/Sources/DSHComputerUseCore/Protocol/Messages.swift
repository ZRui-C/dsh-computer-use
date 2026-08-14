import Foundation

/// A single NDJSON request line: `{"id":"...","method":"...","params":{...}}`.
public struct Request: Codable, Equatable {
    public var id: String
    public var method: String
    public var params: JSONValue

    public init(id: String, method: String, params: JSONValue) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// A single NDJSON response line: `{"id":"...","ok":true,"result":{...}}` or
/// `{"id":"...","ok":false,"error":{...}}`.
public struct Response: Codable, Equatable {
    public var id: String
    public var ok: Bool
    public var result: JSONValue?
    public var error: JSONValue?

    public init(id: String, ok: Bool, result: JSONValue?, error: JSONValue?) {
        self.id = id
        self.ok = ok
        self.result = result
        self.error = error
    }

    public static func success(id: String, result: JSONValue) -> Response {
        Response(id: id, ok: true, result: result, error: nil)
    }

    public static func failure(id: String, error: JSONValue) -> Response {
        Response(id: id, ok: false, result: nil, error: error)
    }
}

/// Structured error payload placed inside a failure response's `error` field.
public struct ErrorPayload: Codable, Equatable {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}
