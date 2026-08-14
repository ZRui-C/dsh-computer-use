import XCTest
import DSHComputerUseCore

final class ProtocolCodableTests: XCTestCase {
    func testJSONValueRoundTrip() throws {
        let value: JSONValue = .object([
            "string": .string("hello"),
            "number": .number(42.5),
            "bool": .bool(true),
            "null": .null,
            "array": .array([.number(1), .number(2), .number(3)]),
            "nested": .object(["key": .string("value")]),
        ])

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testRequestRoundTrip() throws {
        let request = Request(
            id: "req-1",
            method: "performDesktop",
            params: .object([
                "type": .string("click"),
                "point": .object(["x": .number(10), "y": .number(20)]),
            ])
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(Request.self, from: data)
        XCTAssertEqual(decoded, request)
    }

    func testSuccessResponseOmitsError() throws {
        let response = Response.success(id: "1", result: .object(["ok": .bool(true)]))
        let data = try JSONEncoder().encode(response)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["id"] as? String, "1")
        XCTAssertEqual(object?["ok"] as? Bool, true)
        XCTAssertNotNil(object?["result"])
        XCTAssertNil(object?["error"])
    }

    func testFailureResponseOmitsResult() throws {
        let response = Response.failure(
            id: "2",
            error: .object(["code": .string("INVALID_PARAMS"), "message": .string("bad")])
        )
        let data = try JSONEncoder().encode(response)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["ok"] as? Bool, false)
        XCTAssertNotNil(object?["error"])
        XCTAssertNil(object?["result"])
    }

    func testDesktopActionRoundTripAllCases() throws {
        let target = TargetDescriptor(
            bundleId: "com.example.app",
            pid: 123,
            windowId: 77,
            windowFrame: Rect(x: 100, y: 200, width: 800, height: 600),
            role: "AXButton",
            name: "OK",
            identifier: "confirm",
            path: [0, 2]
        )

        let actions: [DesktopAction] = [
            .launchApp(bundleId: "com.example.app", path: nil, appName: nil),
            .launchApp(bundleId: nil, path: "/Applications/Example.app", appName: nil),
            .launchApp(bundleId: nil, path: nil, appName: "Safari"),
            .focus(target: target, background: false),
            .focus(target: target, background: true),
            .click(point: Point(x: 10, y: 20), button: .left, count: 1, target: target),
            .click(point: Point(x: 10, y: 20), button: .right, count: 3, target: nil),
            .doubleClick(point: Point(x: 1, y: 2), target: target),
            .hover(point: Point(x: 3, y: 4), target: target),
            .type(text: "hello world", target: target),
            .press(keys: ["cmd+shift+a", "return"], target: target),
            .scroll(point: Point(x: 5, y: 6), deltaX: 0, deltaY: -100, target: target),
            .drag(from: Point(x: 0, y: 0), to: Point(x: 100, y: 100), button: .left, duration: 0.5, target: target),
            .wait(milliseconds: 250),
            .axAction(action: "AXPress", target: target),
            .setValue(value: "text", target: target),
        ]

        for action in actions {
            let data = try JSONEncoder().encode(action)
            let decoded = try JSONDecoder().decode(DesktopAction.self, from: data)
            XCTAssertEqual(decoded, action, "Round-trip failed for \(action.typeName)")
        }
    }

    func testObservationCodableRoundTrip() throws {
        let node = AXNode(
            role: "AXWindow",
            name: "Window",
            value: "[REDACTED]",
            enabled: true,
            focused: false,
            selected: false,
            secure: true,
            actions: ["AXPress"],
            frame: Rect(x: 0, y: 0, width: 800, height: 600),
            target: TargetDescriptor(pid: 42, path: []),
            depth: 0,
            source: "ax"
        )
        let observation = DesktopObservation(
            timestamp: 1234.5,
            frontmostApp: AppInfo(bundleId: "com.example", name: "Example", pid: 42, path: "/Applications/Example.app"),
            frontmostWindow: WindowInfo(
                title: "Window",
                role: "AXWindow",
                frame: Rect(x: 0, y: 0, width: 800, height: 600),
                windowId: 99
            ),
            mainDisplay: DisplayInfo(frame: Rect(x: 0, y: 0, width: 2560, height: 1440), isMain: true),
            displays: [DisplayInfo(frame: Rect(x: 0, y: 0, width: 2560, height: 1440), isMain: true)],
            permissions: PermissionsReport(accessibility: true, screenCapture: true, aquaSession: true, screenLocked: false),
            warnings: ["Accessibility granted"],
            screenshotPath: "/tmp/shot.png",
            nodes: [node]
        )

        let data = try JSONEncoder().encode(observation)
        let decoded = try JSONDecoder().decode(DesktopObservation.self, from: data)
        XCTAssertEqual(decoded, observation)
    }

    func testOCRResultCodableRoundTrip() throws {
        let result = OCRResult(
            observations: [
                OCRTextObservation(text: "hello", confidence: 0.98, frame: Rect(x: 10, y: 20, width: 100, height: 30))
            ],
            imageSize: Size(width: 1920, height: 1080),
            durationMs: 12.5
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(OCRResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }

    func testReportsCodableRoundTrip() throws {
        let handshake = HandshakeResult(
            protocolVersion: 1,
            helperVersion: "0.2.0",
            appName: "DSHComputerUse",
            platform: "macos",
            capabilities: ["observeDesktop"]
        )
        let status = StatusReport(
            permissions: PermissionsReport(accessibility: false, screenCapture: true, aquaSession: true, screenLocked: false),
            mainDisplayCount: 2,
            socketPath: "/tmp/agent.sock",
            macosVersion: "26.2"
        )
        let actionResult = ActionResult(performed: true, action: "click", method: "ax")

        XCTAssertEqual(handshake, try roundTrip(handshake))
        XCTAssertEqual(status, try roundTrip(status))
        XCTAssertEqual(actionResult, try roundTrip(actionResult))
    }

    func testObserveParamsAndOCRModeRoundTrip() throws {
        let params = ObserveParams(
            maxNodes: 500,
            ocr: .always,
            screenshotPath: "/tmp/obs.png",
            target: TargetDescriptor(pid: 42, windowId: 99, role: "AXWindow", name: "Window")
        )
        XCTAssertEqual(params, try roundTrip(params))
        XCTAssertEqual(OCRMode.auto, try roundTrip(OCRMode.auto))
        XCTAssertEqual(OCRMode.always, try roundTrip(OCRMode.always))
        XCTAssertEqual(OCRMode.never, try roundTrip(OCRMode.never))
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
