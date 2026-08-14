import Foundation
import ApplicationServices
import CoreGraphics

/// Permission checks that never prompt the user.
public enum Permissions {
    /// Whether this process is trusted for Accessibility (AX) control.
    /// Never prompts: returns the current TCC state only.
    public static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Preflights screen-capture / screen-recording access without prompting.
    /// `CGPreflightScreenCaptureAccess()` returns `true` only when the
    /// corresponding TCC permission has already been granted.
    public static var screenCapturePreflight: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// A consolidated `PermissionsReport` snapshot for `status`/`observeDesktop`.
    public static var report: PermissionsReport {
        PermissionsReport(
            accessibility: accessibilityGranted,
            screenCapture: screenCapturePreflight,
            aquaSession: SessionState.aquaSession,
            screenLocked: SessionState.screenLocked
        )
    }
}
