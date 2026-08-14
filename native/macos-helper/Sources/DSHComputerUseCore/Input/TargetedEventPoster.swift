import CoreGraphics
import Darwin
import Foundation

/// The transport used for the most recent synthetic input event.
public enum InputRoute: String, Codable, Equatable {
    case skyLight = "skylight"
    case perProcess = "coregraphics-pid"
    case globalHID = "coregraphics-hid"
}

/// Posts a prebuilt event to one process without moving the user's hardware
/// cursor. Global HID posting is reserved for actions with no process target.
final class TargetedEventPoster {
    func post(
        _ event: CGEvent,
        targetPid: Int32?,
        preferSkyLight: Bool = true
    ) throws -> InputRoute {
        guard let targetPid else {
            event.post(tap: .cghidEventTap)
            return .globalHID
        }

        let pid = pid_t(targetPid)
        guard SkyLightBridge.isRoutableGUIProcess(pid) else {
            throw AgentError.input("Target process \(targetPid) is not a routable GUI application")
        }

        if preferSkyLight, SkyLightBridge.post(event, to: pid) {
            return .skyLight
        }

        event.postToPid(pid)
        return .perProcess
    }
}
