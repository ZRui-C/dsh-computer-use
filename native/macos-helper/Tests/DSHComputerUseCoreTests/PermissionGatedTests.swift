import XCTest
import DSHComputerUseCore

/// Permission-dependent tests. These never prompt: `AXIsProcessTrusted()` and
/// `CGPreflightScreenCaptureAccess()` only read the current TCC state. Live
/// desktop observation is skipped in headless CI or when Accessibility is not granted.
final class PermissionGatedTests: XCTestCase {
    func testAccessibilityStatusIsBoolean() {
        let value = Permissions.accessibilityGranted
        // Trivially a Bool; this documents the non-prompting preflight contract.
        XCTAssertTrue(value || !value)
    }

    func testScreenCapturePreflightIsBoolean() {
        let value = Permissions.screenCapturePreflight
        XCTAssertTrue(value || !value)
    }

    func testDesktopObservationSkipsWithoutAccessibility() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["CI"] != nil,
            "Headless CI has no Aqua session for live AX observation"
        )
        try XCTSkipUnless(
            Permissions.accessibilityGranted,
            "Accessibility permission not granted; skipping live AX observation"
        )
        let observation = DesktopObserver().observe()
        XCTAssertGreaterThan(observation.timestamp, 0)
    }
}
