import AppKit
import CoreGraphics
import Foundation

/// Chromium-compatible targeted click sequence. The event recipe and private
/// field values follow Cua Driver's MIT-licensed macOS implementation.
enum SkyLightBackgroundClick {
    private enum EventKind {
        case moved
        case down
        case up

        var type: CGEventType {
            switch self {
            case .moved: return .mouseMoved
            case .down: return .leftMouseDown
            case .up: return .leftMouseUp
            }
        }
    }

    private struct Step {
        var kind: EventKind
        var primer: Bool
        var clickState: Int64
        var phase: Int64
        var delayAfter: TimeInterval
    }

    static func perform(
        at point: Point,
        button: MouseButton,
        count: Int,
        target: TargetDescriptor
    ) -> Bool {
        guard button == .left,
              (1...2).contains(count),
              let pid = target.pid,
              let windowId = target.windowId,
              let windowFrame = target.windowFrame,
              windowFrame.width > 0,
              windowFrame.height > 0,
              SkyLightBridge.canBackgroundClick,
              SkyLightBridge.windowIsOnScreen(windowId, ownedBy: pid_t(pid)) else {
            return false
        }

        let localPoint = CGPoint(
            x: point.x - windowFrame.x,
            y: point.y - windowFrame.y
        )
        guard CGRect(
            x: 0,
            y: 0,
            width: windowFrame.width,
            height: windowFrame.height
        ).contains(localPoint) else {
            return false
        }
        guard let source = CGEventSource(stateID: .hidSystemState)
            ?? CGEventSource(stateID: .privateState) else {
            return false
        }

        let focusContext: SkyLightSyntheticFocusContext?
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            focusContext = nil
        } else {
            focusContext = SkyLightBridge.beginSyntheticTargetFocus(
                pid: pid_t(pid),
                windowId: windowId
            )
            guard focusContext != nil else { return false }
        }

        var focusIsActive = focusContext != nil
        defer {
            if focusIsActive, let focusContext {
                _ = SkyLightBridge.endSyntheticTargetFocus(focusContext)
            }
        }

        let clickGroupId = Int64(DispatchTime.now().uptimeNanoseconds % 1_000_000_000)
        for step in recipe(clickCount: count) {
            let screenPoint = step.primer ? CGPoint(x: -1, y: -1) : point.cgPoint
            let windowPoint = step.primer ? CGPoint(x: -1, y: -1) : localPoint
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: step.kind.type,
                mouseCursorPosition: screenPoint,
                mouseButton: .left
            ), SkyLightBridge.stampMouseEvent(
                event,
                pid: pid_t(pid),
                windowId: windowId,
                windowPoint: windowPoint,
                clickState: step.clickState,
                phase: step.phase,
                clickGroupId: clickGroupId
            ), SkyLightBridge.post(event, to: pid_t(pid)) else {
                return false
            }

            // This deliberate dual dispatch mirrors Cua: SkyLight reaches
            // Chromium/Catalyst, while the public route preserves AppKit.
            event.postToPid(pid_t(pid))
            if step.delayAfter > 0 {
                Thread.sleep(forTimeInterval: step.delayAfter)
            }
        }

        if let focusContext {
            Thread.sleep(forTimeInterval: 0.100)
            guard SkyLightBridge.endSyntheticTargetFocus(focusContext) else { return false }
            focusIsActive = false
        }
        return true
    }

    private static func recipe(clickCount: Int) -> [Step] {
        var steps = [
            Step(kind: .moved, primer: false, clickState: 0, phase: 2, delayAfter: 0.015),
            Step(kind: .down, primer: true, clickState: 1, phase: 1, delayAfter: 0.001),
            Step(kind: .up, primer: true, clickState: 1, phase: 2, delayAfter: 0.100),
        ]
        for pairIndex in 1...clickCount {
            steps.append(Step(
                kind: .down,
                primer: false,
                clickState: Int64(pairIndex),
                phase: 3,
                delayAfter: 0.001
            ))
            steps.append(Step(
                kind: .up,
                primer: false,
                clickState: Int64(pairIndex),
                phase: 3,
                delayAfter: pairIndex < clickCount ? 0.080 : 0
            ))
        }
        return steps
    }
}
