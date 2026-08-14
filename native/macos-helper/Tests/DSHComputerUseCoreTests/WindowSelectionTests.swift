import XCTest
@testable import DSHComputerUseCore

final class WindowSelectionTests: XCTestCase {
    private let candidates = [
        CaptureWindowCandidate(
            windowId: 10,
            pid: 42,
            title: "Primary",
            frame: Rect(x: 100, y: 100, width: 800, height: 600),
            isOnScreen: true,
            layer: 0
        ),
        CaptureWindowCandidate(
            windowId: 11,
            pid: 42,
            title: "Secondary",
            frame: Rect(x: 940, y: 100, width: 600, height: 500),
            isOnScreen: true,
            layer: 0
        ),
        CaptureWindowCandidate(
            windowId: 20,
            pid: 99,
            title: "Other app",
            frame: Rect(x: 0, y: 0, width: 400, height: 300),
            isOnScreen: true,
            layer: 0
        ),
    ]

    func testWindowIdWinsWithinTargetProcess() {
        let selected = ScreenCaptureManager.selectCandidate(
            candidates,
            target: TargetDescriptor(pid: 42, windowId: 11)
        )
        XCTAssertEqual(selected?.windowId, 11)
    }

    func testWindowTitleAndFrameResolveWithoutWindowId() {
        let byTitle = ScreenCaptureManager.selectCandidate(
            candidates,
            target: TargetDescriptor(pid: 42, role: "AXWindow", name: "Primary")
        )
        XCTAssertEqual(byTitle?.windowId, 10)

        let byFrame = ScreenCaptureManager.selectCandidate(
            candidates,
            target: TargetDescriptor(pid: 42),
            fallbackFrame: Rect(x: 942, y: 101, width: 599, height: 501)
        )
        XCTAssertEqual(byFrame?.windowId, 11)
    }

    func testAmbiguousPidOnlySelectionFailsClosed() {
        let selected = ScreenCaptureManager.selectCandidate(
            candidates,
            target: TargetDescriptor(pid: 42)
        )
        XCTAssertNil(selected)
    }
}
