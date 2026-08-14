import Foundation
import CoreGraphics

/// Serializes desktop input so key and pointer sequences cannot interleave.
public final class InputQueue {
    private let queue = DispatchQueue(label: "com.deepseek.agent.desktop-input", qos: .userInteractive)

    public init() {}

    @discardableResult
    public func perform<T>(globalSafety: Bool = false, _ body: () throws -> T) throws -> T {
        var boxed: Result<T, Error>?
        queue.sync {
            boxed = Result {
                defer {
                    if globalSafety { InputSafety.releaseAll() }
                }
                return try body()
            }
        }
        return try boxed!.get()
    }
}

/// Clears global HID state only after actions that actually use the global
/// input stream. Background per-process actions must not disturb the user's
/// physical buttons or modifier keys.
public enum InputSafety {
    public static func releaseAll() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let current = CGEvent(source: nil)?.location ?? CGPoint.zero
        for button in [CGMouseButton.left, .right, .center] {
            let event = CGEvent(
                mouseEventSource: source,
                mouseType: upType(for: button),
                mouseCursorPosition: current,
                mouseButton: button
            )
            event?.post(tap: .cghidEventTap)
        }
        if let flags = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            flags.type = .flagsChanged
            flags.flags = []
            flags.post(tap: .cghidEventTap)
        }
    }

    private static func upType(for button: CGMouseButton) -> CGEventType {
        switch button {
        case .left: return .leftMouseUp
        case .right: return .rightMouseUp
        case .center: return .otherMouseUp
        @unknown default: return .otherMouseUp
        }
    }
}

/// Emits input through SkyLight or CoreGraphics per-process routing whenever a
/// target pid is available. Actions without a pid preserve the previous global
/// HID behavior.
public final class DesktopInput {
    private let queue = InputQueue()
    private let poster = TargetedEventPoster()
    private let source = CGEventSource(stateID: .hidSystemState)
        ?? CGEventSource(stateID: .privateState)!

    public init() {}

    public func move(to point: Point, targetPid: Int32? = nil) throws -> InputRoute {
        try queue.perform(globalSafety: targetPid == nil) {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: point.cgPoint,
                mouseButton: .left
            ) else {
                throw AgentError.input("Failed to create mouse move event")
            }
            return try poster.post(
                event,
                targetPid: targetPid,
                preferSkyLight: targetPid == nil
            )
        }
    }

    public func click(
        at point: Point,
        button: MouseButton,
        count: Int,
        target: TargetDescriptor? = nil
    ) throws -> InputRoute {
        let targetPid = target?.pid
        return try queue.perform(globalSafety: targetPid == nil) {
            if let target,
               SkyLightBackgroundClick.perform(
                   at: point,
                   button: button,
                   count: max(1, count),
                   target: target
               ) {
                return .skyLight
            }
            if targetPid == nil {
                let move = try makeMouseEvent(type: .mouseMoved, point: point, button: button.cgMouseButton)
                _ = try poster.post(move, targetPid: nil)
            }

            let clickCount = max(1, count)
            var lastRoute: InputRoute = targetPid == nil ? .globalHID : .perProcess
            for index in 0..<clickCount {
                let state = Int64(index + 1)
                let down = try makeMouseEvent(
                    type: downType(for: button.cgMouseButton),
                    point: point,
                    button: button.cgMouseButton,
                    clickState: state
                )
                let up = try makeMouseEvent(
                    type: upType(for: button.cgMouseButton),
                    point: point,
                    button: button.cgMouseButton,
                    clickState: state
                )
                lastRoute = try poster.post(
                    down,
                    targetPid: targetPid,
                    preferSkyLight: targetPid == nil
                )
                usleep(10_000)
                lastRoute = try poster.post(
                    up,
                    targetPid: targetPid,
                    preferSkyLight: targetPid == nil
                )
                if index + 1 < clickCount { usleep(40_000) }
            }
            return lastRoute
        }
    }

    public func scroll(
        at point: Point,
        deltaX: Double,
        deltaY: Double,
        targetPid: Int32? = nil
    ) throws -> InputRoute {
        try queue.perform(globalSafety: targetPid == nil) {
            if targetPid == nil {
                let move = try makeMouseEvent(type: .mouseMoved, point: point, button: .left)
                _ = try poster.post(move, targetPid: nil)
            }

            guard let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(deltaY),
                wheel2: Int32(deltaX),
                wheel3: 0
            ) else {
                throw AgentError.input("Failed to create scroll event")
            }
            event.location = point.cgPoint
            return try poster.post(
                event,
                targetPid: targetPid,
                preferSkyLight: targetPid == nil
            )
        }
    }

    public func drag(
        from: Point,
        to: Point,
        button: MouseButton,
        duration: Double,
        targetPid: Int32? = nil
    ) throws -> InputRoute {
        try queue.perform(globalSafety: targetPid == nil) {
            if targetPid == nil {
                let move = try makeMouseEvent(type: .mouseMoved, point: from, button: button.cgMouseButton)
                _ = try poster.post(move, targetPid: nil)
            }

            let down = try makeMouseEvent(
                type: downType(for: button.cgMouseButton),
                point: from,
                button: button.cgMouseButton
            )
            let up = try makeMouseEvent(
                type: upType(for: button.cgMouseButton),
                point: to,
                button: button.cgMouseButton
            )
            var released = false
            defer {
                if !released {
                    _ = try? poster.post(up, targetPid: targetPid, preferSkyLight: targetPid == nil)
                }
            }

            var lastRoute = try poster.post(
                down,
                targetPid: targetPid,
                preferSkyLight: targetPid == nil
            )
            let steps = max(1, Int(max(0, duration) * 60))
            let delay = duration > 0 ? duration / Double(steps) : 0
            for step in 1...steps {
                let progress = Double(step) / Double(steps)
                let point = Point(
                    x: from.x + (to.x - from.x) * progress,
                    y: from.y + (to.y - from.y) * progress
                )
                let drag = try makeMouseEvent(
                    type: dragType(for: button.cgMouseButton),
                    point: point,
                    button: button.cgMouseButton
                )
                lastRoute = try poster.post(
                    drag,
                    targetPid: targetPid,
                    preferSkyLight: targetPid == nil
                )
                if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            }
            lastRoute = try poster.post(
                up,
                targetPid: targetPid,
                preferSkyLight: targetPid == nil
            )
            released = true
            return lastRoute
        }
    }

    public func type(_ text: String, targetPid: Int32? = nil) throws -> InputRoute {
        try queue.perform(globalSafety: targetPid == nil) {
            var lastRoute: InputRoute = targetPid == nil ? .globalHID : .perProcess
            for character in text {
                let units = Array(String(character).utf16)
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                    throw AgentError.input("Failed to create Unicode keyboard event")
                }
                down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                lastRoute = try poster.post(down, targetPid: targetPid)
                lastRoute = try poster.post(up, targetPid: targetPid)
                usleep(5_000)
            }
            return lastRoute
        }
    }

    public func press(_ chord: KeyChord, targetPid: Int32? = nil) throws -> InputRoute {
        try queue.perform(globalSafety: targetPid == nil) {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: false) else {
                throw AgentError.input("Failed to create keyboard event")
            }
            down.flags = chord.modifiers
            up.flags = chord.modifiers
            _ = try poster.post(down, targetPid: targetPid)
            return try poster.post(up, targetPid: targetPid)
        }
    }

    public func wait(milliseconds: Int) {
        if milliseconds > 0 {
            Thread.sleep(forTimeInterval: Double(milliseconds) / 1_000.0)
        }
    }

    private func makeMouseEvent(
        type: CGEventType,
        point: Point,
        button: CGMouseButton,
        clickState: Int64? = nil
    ) throws -> CGEvent {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point.cgPoint,
            mouseButton: button
        ) else {
            throw AgentError.input("Failed to create mouse event")
        }
        if let clickState {
            event.setIntegerValueField(.mouseEventClickState, value: clickState)
        }
        return event
    }

    private func downType(for button: CGMouseButton) -> CGEventType {
        switch button {
        case .left: return .leftMouseDown
        case .right: return .rightMouseDown
        case .center: return .otherMouseDown
        @unknown default: return .otherMouseDown
        }
    }

    private func upType(for button: CGMouseButton) -> CGEventType {
        switch button {
        case .left: return .leftMouseUp
        case .right: return .rightMouseUp
        case .center: return .otherMouseUp
        @unknown default: return .otherMouseUp
        }
    }

    private func dragType(for button: CGMouseButton) -> CGEventType {
        switch button {
        case .left: return .leftMouseDragged
        case .right: return .rightMouseDragged
        case .center: return .otherMouseDragged
        @unknown default: return .otherMouseDragged
        }
    }
}
