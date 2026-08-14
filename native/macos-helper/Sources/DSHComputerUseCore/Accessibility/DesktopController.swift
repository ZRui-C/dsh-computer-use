import Foundation
import AppKit
import ApplicationServices

/// Executes desktop actions with AX semantics first, then process-targeted input,
/// and global HID only when no process target is available.
public final class DesktopController {
    private let input = DesktopInput()
    private let cancellation: CancellationRegistry?

    public init(cancellation: CancellationRegistry? = nil) {
        self.cancellation = cancellation
    }

    public func perform(_ action: DesktopAction, requestId: String? = nil) throws -> ActionResult {
        switch action {
        case .launchApp(let bundleId, let path, let appName):
            try launchApp(bundleId: bundleId, path: path, appName: appName)
            return ActionResult(performed: true, action: action.typeName, method: "ns-workspace")

        case .focus(let target, let background):
            return try focus(target: target, background: background)

        case .click(let point, let button, let count, let target):
            return try click(point: point, button: button, count: count, target: target)

        case .doubleClick(let point, let target):
            return try click(point: point, button: .left, count: 2, target: target)

        case .hover(let point, let target):
            let route = try input.move(to: point, targetPid: target?.pid)
            updateCursor(point: point, route: route)
            return routeResult(action: action.typeName, route: route)

        case .type(let text, let target):
            focusAXElement(target)
            let route = try input.type(text, targetPid: target?.pid)
            return routeResult(action: action.typeName, route: route)

        case .press(let keys, let target):
            focusAXElement(target)
            var route: InputRoute = target?.pid == nil ? .globalHID : .perProcess
            for keyString in keys {
                guard let chord = KeyChordParser.parse(keyString) else {
                    throw AgentError.invalidParams("Unparseable key chord: \(keyString)")
                }
                route = try input.press(chord, targetPid: target?.pid)
            }
            return routeResult(action: action.typeName, route: route)

        case .scroll(let point, let deltaX, let deltaY, let target):
            let route = try input.scroll(
                at: point,
                deltaX: deltaX,
                deltaY: deltaY,
                targetPid: target?.pid
            )
            updateCursor(point: point, route: route)
            return routeResult(action: action.typeName, route: route)

        case .drag(let from, let to, let button, let duration, let target):
            let route = try input.drag(
                from: from,
                to: to,
                button: button,
                duration: duration,
                targetPid: target?.pid
            )
            updateCursor(point: to, route: route)
            return routeResult(action: action.typeName, route: route)

        case .wait(let milliseconds):
            try wait(milliseconds: milliseconds, requestId: requestId)
            return ActionResult(performed: true, action: action.typeName, method: "wait")

        case .axAction(let actionName, let target):
            return try axAction(action: actionName, target: target)

        case .setValue(let value, let target):
            return try setValue(value: value, target: target)
        }
    }

    private func launchApp(bundleId: String?, path: String?, appName: String?) throws {
        if let path, !path.isEmpty {
            try openApplication(at: URL(fileURLWithPath: path))
            return
        }
        if let bundleId, !bundleId.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            try openApplication(at: url)
            return
        }
        if let appName, !appName.isEmpty {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", appName]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw AgentError.input("Failed to launch app '\(appName)' (open exited \(process.terminationStatus))")
            }
            return
        }
        throw AgentError.invalidParams("launchApp requires a non-empty bundleId, path, or appName")
    }

    private func openApplication(at url: URL) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var openError: Error?
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            openError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let openError {
            throw AgentError.input("Failed to launch application: \(openError.localizedDescription)")
        }
    }

    private func focus(target: TargetDescriptor?, background: Bool) throws -> ActionResult {
        if background, let pid = target?.pid {
            if focusAXElement(target) {
                return ActionResult(performed: true, action: "focus", method: "ax-background")
            }
            throw AgentError.input("Could not focus target process \(pid) without raising it")
        }

        if let pid = target?.pid,
           let runningApp = NSRunningApplication(processIdentifier: pid) {
            runningApp.activate(options: [.activateAllWindows])
        }
        if focusAXElement(target) {
            return ActionResult(performed: true, action: "focus", method: "ax")
        }
        return ActionResult(performed: true, action: "focus", method: "ns-running-app")
    }

    private func click(
        point: Point,
        button: MouseButton,
        count: Int,
        target: TargetDescriptor?
    ) throws -> ActionResult {
        if count == 1 {
            let element: AXUIElement?
            if let target {
                element = AXAccessibility.resolve(target)
            } else {
                element = AXAccessibility.element(at: point)
            }
            if let element, AXAccessibility.performPress(element) {
                if target?.pid != nil { VirtualCursorOverlay.shared.show(at: point) }
                return ActionResult(performed: true, action: "click", method: "ax")
            }
        }

        let route = try input.click(
            at: point,
            button: button,
            count: count,
            target: target
        )
        updateCursor(point: point, route: route)
        return routeResult(action: "click", route: route)
    }

    private func axAction(action: String, target: TargetDescriptor?) throws -> ActionResult {
        guard let target else {
            throw AgentError.invalidParams("axAction requires a target descriptor")
        }
        guard let element = AXAccessibility.resolve(target) else {
            throw AgentError.accessibility("Could not resolve target descriptor")
        }
        guard AXAccessibility.performAction(action, on: element) else {
            throw AgentError.accessibility("AX action '\(action)' failed")
        }
        return ActionResult(performed: true, action: "axAction", method: "ax", detail: action)
    }

    private func setValue(value: String, target: TargetDescriptor?) throws -> ActionResult {
        guard let target else {
            throw AgentError.invalidParams("setValue requires a target descriptor")
        }
        guard let element = AXAccessibility.resolve(target) else {
            throw AgentError.accessibility("Could not resolve target descriptor")
        }
        guard AXAccessibility.setValue(value, on: element) else {
            throw AgentError.accessibility("AX setValue failed")
        }
        return ActionResult(performed: true, action: "setValue", method: "ax")
    }

    @discardableResult
    private func focusAXElement(_ target: TargetDescriptor?) -> Bool {
        guard let target, let element = AXAccessibility.resolve(target) else { return false }
        return AXAccessibility.setFocused(element, focused: true)
    }

    private func routeResult(action: String, route: InputRoute) -> ActionResult {
        ActionResult(performed: true, action: action, method: route.rawValue)
    }

    private func updateCursor(point: Point, route: InputRoute) {
        if route == .globalHID {
            VirtualCursorOverlay.shared.hide()
        } else {
            VirtualCursorOverlay.shared.show(at: point)
        }
    }

    private func wait(milliseconds: Int, requestId: String?) throws {
        let start = Date()
        let total = Double(milliseconds) / 1_000.0
        while Date().timeIntervalSince(start) < total {
            if let requestId, cancellation?.isCancelled(requestId) == true {
                throw AgentError.cancelled("Operation cancelled for request \(requestId)")
            }
            let remaining = total - Date().timeIntervalSince(start)
            Thread.sleep(forTimeInterval: min(0.05, remaining))
        }
    }
}
