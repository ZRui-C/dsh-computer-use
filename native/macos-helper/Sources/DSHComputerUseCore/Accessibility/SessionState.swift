import Foundation
import CoreGraphics
import AppKit

/// Reads the current Aqua GUI session and screen-lock state without prompting.
public enum SessionState {
    /// Whether a window-server GUI session exists for the current user.
    public static var aquaSession: Bool {
        CGSessionCopyCurrentDictionary() != nil
    }

    /// Best-effort screen-lock detection.
    ///
    /// 1. The private `kCGSSessionScreenIsLockedKey` entry (present only while
    ///    locked on many macOS versions).
    /// 2. Fallback: a running ScreenSaverEngine implies the screen is locked or
    ///    the screensaver is active.
    public static var screenLocked: Bool {
        if let dict = CGSessionCopyCurrentDictionary() as? [String: Any],
           let locked = dict["kCGSSessionScreenIsLockedKey"] as? Bool {
            return locked
        }
        let apps = NSWorkspace.shared.runningApplications
        return apps.contains { $0.bundleIdentifier == "com.apple.ScreenSaver.Engine" }
            || apps.contains { $0.localizedName == "ScreenSaverEngine" }
    }
}
