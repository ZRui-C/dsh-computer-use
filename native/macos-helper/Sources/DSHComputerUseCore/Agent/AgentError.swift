import Foundation

/// Errors surfaced through the protocol's `error` payload.
public enum AgentError: Error, Equatable, LocalizedError {
    case invalidParams(String)
    case unknownMethod(String)
    case socket(String)
    case accessibility(String)
    case input(String)
    case ocr(String)
    case cancelled(String)

    public var code: String {
        switch self {
        case .invalidParams: return "INVALID_PARAMS"
        case .unknownMethod: return "UNKNOWN_METHOD"
        case .socket: return "SOCKET_ERROR"
        case .accessibility: return "ACCESSIBILITY_ERROR"
        case .input: return "INPUT_ERROR"
        case .ocr: return "OCR_ERROR"
        case .cancelled: return "CANCELLED"
        }
    }

    public var errorDescription: String? { message }

    public var message: String {
        switch self {
        case .invalidParams(let m),
             .unknownMethod(let m),
             .socket(let m),
             .accessibility(let m),
             .input(let m),
             .ocr(let m),
             .cancelled(let m):
            return m
        }
    }
}
