import Foundation

/// Routes protocol requests to the underlying services and produces responses.
public final class ComputerUseAgent {
    /// Integer wire protocol version.
    public static let protocolVersion = 1
    /// Helper's own semver.
    public static let helperVersion = "0.3.0"
    public static let appName = "DSHComputerUse"

    public let observer = DesktopObserver()
    public let controller: DesktopController
    public let ocr = VisionOCRService()
    public let screenCapture = ScreenCaptureManager()
    public let cancellation = CancellationRegistry()

    public var socketPath: String?

    public init() {
        controller = DesktopController(cancellation: cancellation)
    }

    public func handle(request: Request) -> Response {
        do {
            let result = try handleMethod(request.method, params: request.params, requestId: request.id)
            cancellation.clear(request.id)
            return .success(id: request.id, result: result)
        } catch {
            cancellation.clear(request.id)
            let payload = errorPayload(for: error)
            return .failure(id: request.id, error: payload)
        }
    }

    private func handleMethod(_ method: String, params: JSONValue, requestId: String) throws -> JSONValue {
        switch method {
        case "handshake":
            return try CodableBridge.toJSONValue(HandshakeResult(
                protocolVersion: Self.protocolVersion,
                helperVersion: Self.helperVersion,
                appName: Self.appName,
                platform: "macos",
                capabilities: capabilities()
            ))

        case "status":
            let capture = screenCapture.captureInfo()
            return try CodableBridge.toJSONValue(StatusReport(
                permissions: Permissions.report,
                mainDisplayCount: capture.mainDisplayCount,
                socketPath: socketPath,
                macosVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                architecture: architectureName()
            ))

        case "observeDesktop":
            let observeParams: ObserveParams = (try? CodableBridge.fromJSONValue(params))
                ?? ObserveParams()
            return try CodableBridge.toJSONValue(observer.observe(params: observeParams))

        case "performDesktop":
            let action: DesktopAction = try CodableBridge.fromJSONValue(params)
            let result = try controller.perform(action, requestId: requestId)
            return try CodableBridge.toJSONValue(result)

        case "ocrFile":
            let request: OCRFileRequest = try CodableBridge.fromJSONValue(params)
            let result = try ocr.recognize(imageURL: URL(fileURLWithPath: request.path))
            return try CodableBridge.toJSONValue(result)

        case "shutdown":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                exit(0)
            }
            return try CodableBridge.toJSONValue(ActionResult(
                performed: true,
                action: "shutdown",
                method: "process"
            ))

        case "cancel":
            // Best-effort cancellation of an in-flight request id. The driver
            // sends `{ requestId: "<id of the request to cancel>" }`.
            if let dict = params.dictionary,
               let target = dict["requestId"]?.stringValue ?? dict["id"]?.stringValue {
                cancellation.cancel(target)
            }
            return try CodableBridge.toJSONValue(ActionResult(
                performed: true,
                action: "cancel",
                method: "registry"
            ))

        default:
            throw AgentError.unknownMethod("Unknown method: \(method)")
        }
    }

    private func errorPayload(for error: Error) -> JSONValue {
        let payload: ErrorPayload
        if let agentError = error as? AgentError {
            payload = ErrorPayload(code: agentError.code, message: agentError.message)
        } else if let decoding = error as? DecodingError {
            payload = ErrorPayload(code: "INVALID_PARAMS", message: String(describing: decoding))
        } else {
            payload = ErrorPayload(code: "INTERNAL_ERROR", message: error.localizedDescription)
        }
        return (try? CodableBridge.toJSONValue(payload)) ?? .object([
            "code": .string(payload.code),
            "message": .string(payload.message),
        ])
    }

    private func capabilities() -> [String] {
        var result = [
            "handshake", "status", "observeDesktop", "performDesktop", "ocrFile", "shutdown",
            "ax-input", "coregraphics-input", "coregraphics-pid-input", "vision-ocr",
            "screen-capture", "window-capture", "virtual-cursor",
        ]
        if SkyLightBridge.canPostToProcess { result.append("skylight-input") }
        if SkyLightBridge.canFocusWithoutRaise { result.append("skylight-focus-without-raise") }
        return result
    }

    private func architectureName() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
