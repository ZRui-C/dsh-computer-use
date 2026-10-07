import Foundation
import ApplicationServices
import CoreGraphics

/// Attribute-name constants. Referenced as plain `String`s so the module avoids
/// any CFString/String bridging ambiguity from the AX headers.
public enum AXAttribute {
    public static let role = "AXRole"
    public static let subrole = "AXSubrole"
    public static let title = "AXTitle"
    public static let value = "AXValue"
    public static let description = "AXDescription"
    public static let enabled = "AXEnabled"
    public static let focused = "AXFocused"
    public static let selected = "AXSelected"
    public static let position = "AXPosition"
    public static let size = "AXSize"
    public static let children = "AXChildren"
    public static let windows = "AXWindows"
    public static let focusedWindow = "AXFocusedWindow"
    public static let mainWindow = "AXMainWindow"
    public static let parent = "AXParent"
    public static let pressAction = "AXPress"
}

/// Role-name constants for secure-value redaction and general classification.
public enum AXRole {
    public static let textField = "AXTextField"
    public static let secureTextField = "AXSecureTextField"
    public static let window = "AXWindow"
    public static let button = "AXButton"
}

/// AX traversal cutoffs are distinct from an empty or fully captured tree.
public struct AXObservationResult {
    public var nodes: [AXNode]
    public var hitDepthLimit: Bool
    public var hitNodeLimit: Bool

    public var truncated: Bool { hitDepthLimit || hitNodeLimit }
}

/// Pure traversal logic, shared by live AX observation and permission-free tests.
enum AXTreeTraversal {
    static func observe<Element>(
        root: Element,
        maxDepth: Int,
        maxNodes: Int,
        children: (Element, Int) -> [Element],
        makeNode: (Element, Int, [Int]) -> AXNode
    ) -> AXObservationResult {
        let depthLimit = max(0, min(maxDepth, AXAccessibility.maximumDepth))
        let nodeLimit = max(0, min(maxNodes, AXAccessibility.maximumNodes))
        var result = AXObservationResult(nodes: [], hitDepthLimit: false, hitNodeLimit: false)
        guard nodeLimit > 0 else {
            result.hitNodeLimit = true
            return result
        }

        var pending: [(element: Element, path: [Int])] = [(root, [])]
        while let current = pending.popLast() {
            let depth = current.path.count
            result.nodes.append(makeNode(current.element, depth, current.path))
            let remaining = nodeLimit - result.nodes.count

            // Read only the child prefix that can fit, plus one overflow probe.
            // At a depth cutoff even one child proves that the tree is partial.
            let childrenToRead = depth == depthLimit ? 1 : remaining + 1
            let kids = children(current.element, childrenToRead)
            if depth == depthLimit {
                result.hitDepthLimit = result.hitDepthLimit || !kids.isEmpty
                if remaining == 0, !pending.isEmpty {
                    result.hitNodeLimit = true
                    break
                }
                continue
            }

            let childCount = min(kids.count, remaining)
            if kids.count > childCount { result.hitNodeLimit = true }

            // New descendants precede already queued siblings in DFS order.
            // Drop only entries beyond the remaining budget, keeping memory
            // bounded even for a very wide or cyclic accessibility tree.
            let pendingCapacity = remaining - childCount
            if pending.count > pendingCapacity {
                pending.removeFirst(pending.count - pendingCapacity)
                result.hitNodeLimit = true
            }
            for index in (0..<childCount).reversed() {
                pending.append((kids[index], current.path + [index]))
            }
        }
        return result
    }
}

/// Thin, synchronous wrappers over the AX C API. Every element query applies a
/// short messaging timeout so a hung target application cannot block the agent.
public enum AXAccessibility {
    public static let messagingTimeout: Float = 1.0
    // Browser web areas can sit well below eight native container levels.
    public static let defaultMaxDepth = 64
    public static let maximumDepth = 256
    public static let maximumNodes = 2_000

    public static func prepare(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
    }

    public static func systemWide() -> AXUIElement {
        AXUIElementCreateSystemWide()
    }

    public static func application(pid: Int32) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    /// Safely downcasts a `CFTypeRef` to a CoreFoundation type by comparing
    /// type IDs, avoiding the "downcast always succeeds" diagnostic that a plain
    /// `as?` cast triggers for CF types.
    private static func cfCast<T>(_ raw: CFTypeRef?, typeID: CFTypeID, as: T.Type) -> T? {
        guard let raw = raw, CFGetTypeID(raw) == typeID else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }

    // MARK: Attribute access

    public static func rawAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        prepare(element)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == AXError.success else { return nil }
        return value
    }

    public static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let raw = rawAttribute(element, attribute) else { return nil }
        if let string = raw as? String { return string }
        if let number = raw as? NSNumber { return number.stringValue }
        return String(describing: raw)
    }

    public static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let raw = rawAttribute(element, attribute) else { return nil }
        if let bool = raw as? Bool { return bool }
        if let number = raw as? NSNumber { return number.boolValue }
        return nil
    }

    public static func stringArrayAttribute(_ element: AXUIElement, _ attribute: String) -> [String] {
        guard let raw = rawAttribute(element, attribute) else { return [] }
        guard let array = raw as? [String] else { return [] }
        return array
    }

    public static func frameAttribute(_ element: AXUIElement) -> Rect? {
        guard let position = cfCast(
            rawAttribute(element, AXAttribute.position),
            typeID: AXValueGetTypeID(),
            as: AXValue.self
        ),
        let size = cfCast(
            rawAttribute(element, AXAttribute.size),
            typeID: AXValueGetTypeID(),
            as: AXValue.self
        ) else {
            return nil
        }
        var point = CGPoint.zero
        var sizeValue = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point),
              AXValueGetValue(size, .cgSize, &sizeValue) else {
            return nil
        }
        return Rect(CGRect(origin: point, size: sizeValue))
    }

    // MARK: Element lookup

    public static func element(at point: Point) -> AXUIElement? {
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            systemWide(),
            Float(point.x),
            Float(point.y),
            &element
        )
        guard error == AXError.success else { return nil }
        return element
    }

    public static func focusedWindow(_ app: AXUIElement) -> AXUIElement? {
        cfCast(
            rawAttribute(app, AXAttribute.focusedWindow),
            typeID: AXUIElementGetTypeID(),
            as: AXUIElement.self
        )
    }

    public static func mainWindow(_ app: AXUIElement) -> AXUIElement? {
        cfCast(
            rawAttribute(app, AXAttribute.mainWindow),
            typeID: AXUIElementGetTypeID(),
            as: AXUIElement.self
        )
    }

    public static func windows(_ app: AXUIElement) -> [AXUIElement] {
        guard let raw = rawAttribute(app, AXAttribute.windows),
              let windows = raw as? [AXUIElement] else {
            return []
        }
        return windows
    }

    public static func window(_ app: AXUIElement, matching target: TargetDescriptor?) -> AXUIElement? {
        guard let target else { return focusedWindow(app) ?? mainWindow(app) }
        let candidates = windows(app)
        guard !candidates.isEmpty else { return focusedWindow(app) ?? mainWindow(app) }

        if target.role == AXRole.window {
            if let name = target.name {
                let titleMatches = candidates.filter { stringAttribute($0, AXAttribute.title) == name }
                if titleMatches.count == 1 { return titleMatches[0] }
            }
            if let frame = target.frame,
               let closest = closestWindow(to: frame, candidates: candidates) {
                return closest
            }
        }

        if let elementFrame = target.frame {
            let center = CGPoint(
                x: elementFrame.x + elementFrame.width / 2,
                y: elementFrame.y + elementFrame.height / 2
            )
            let containing = candidates.filter { candidate in
                frameAttribute(candidate)?.cgRect.contains(center) == true
            }
            if containing.count == 1 { return containing[0] }
        }
        return focusedWindow(app) ?? mainWindow(app) ?? candidates.first
    }

    public static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let raw = rawAttribute(element, AXAttribute.children) else { return [] }
        guard let array = raw as? [AXUIElement] else { return [] }
        return array
    }

    /// Observation must not copy an app's entire AXChildren array just to use a
    /// small prefix. Child indexes remain unchanged for serialized target paths.
    private static func children(_ element: AXUIElement, limit: Int) -> [AXUIElement] {
        guard limit > 0 else { return [] }
        prepare(element)
        var values: CFArray?
        let error = AXUIElementCopyAttributeValues(
            element, AXAttribute.children as CFString, 0, limit, &values
        )
        guard error == .success, let array = values as? [AXUIElement] else { return [] }
        return array
    }

    // MARK: Actions

    /// Actions are provided by a dedicated AX API, not an AXActions attribute.
    public static func actionNames(_ element: AXUIElement) -> [String] {
        actionNames(element, copyActionNames: AXUIElementCopyActionNames)
    }

    static func actionNames(
        _ element: AXUIElement,
        copyActionNames: (AXUIElement, UnsafeMutablePointer<CFArray?>) -> AXError
    ) -> [String] {
        prepare(element)
        var names: CFArray?
        guard copyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    public static func performPress(_ element: AXUIElement) -> Bool {
        performPress(element, actionNames: actionNames, performAction: performAction)
    }

    static func performPress(
        _ element: AXUIElement,
        actionNames: (AXUIElement) -> [String],
        performAction: (String, AXUIElement) -> Bool
    ) -> Bool {
        let actions = actionNames(element)
        guard actions.contains(AXAttribute.pressAction) else { return false }
        return performAction(AXAttribute.pressAction, element)
    }

    public static func performAction(_ action: String, on element: AXUIElement) -> Bool {
        prepare(element)
        return AXUIElementPerformAction(element, action as CFString) == AXError.success
    }

    public static func setValue(_ value: String, on element: AXUIElement) -> Bool {
        return AXUIElementSetAttributeValue(element, AXAttribute.value as CFString, value as CFString) == AXError.success
    }

    public static func setFocused(_ element: AXUIElement, focused: Bool) -> Bool {
        return AXUIElementSetAttributeValue(
            element,
            AXAttribute.focused as CFString,
            focused ? kCFBooleanTrue : kCFBooleanFalse
        ) == AXError.success
    }

    /// Re-resolves a serialized target descriptor to a live AX element.
    public static func resolve(_ target: TargetDescriptor) -> AXUIElement? {
        guard let pid = target.pid else { return nil }
        let app = application(pid: pid)
        prepare(app)
        guard let window = window(app, matching: target) else { return nil }
        guard let path = target.path, !path.isEmpty else { return window }

        var current = window
        for index in path {
            let kids = children(current)
            guard index >= 0 && index < kids.count else { return nil }
            current = kids[index]
        }
        return current
    }

    // MARK: Observation

    /// Builds a bounded, flat AX node list rooted at the selected window. Each
    /// node carries its tree `depth` and a `source` of `"ax"`.
    public static func observe(
        app: AXUIElement,
        pid: Int32,
        target: TargetDescriptor? = nil,
        maxDepth: Int = defaultMaxDepth,
        maxNodes: Int
    ) -> [AXNode] {
        observeWithDiagnostics(
            app: app,
            pid: pid,
            target: target,
            maxDepth: maxDepth,
            maxNodes: maxNodes
        ).nodes
    }

    public static func observeWithDiagnostics(
        app: AXUIElement,
        pid: Int32,
        target: TargetDescriptor? = nil,
        maxDepth: Int = defaultMaxDepth,
        maxNodes: Int
    ) -> AXObservationResult {
        guard let window = window(app, matching: target) else {
            return AXObservationResult(nodes: [], hitDepthLimit: false, hitNodeLimit: false)
        }
        return AXTreeTraversal.observe(
            root: window,
            maxDepth: maxDepth,
            maxNodes: maxNodes,
            children: { children($0, limit: $1) },
            makeNode: { makeNode($0, pid: pid, depth: $1, path: $2) }
        )
    }

    static func makeNode(
        _ element: AXUIElement,
        pid: Int32,
        depth: Int,
        path: [Int],
        stringAttribute: (AXUIElement, String) -> String? = AXAccessibility.stringAttribute,
        boolAttribute: (AXUIElement, String) -> Bool? = AXAccessibility.boolAttribute,
        frameAttribute: (AXUIElement) -> Rect? = AXAccessibility.frameAttribute,
        actionNames: (AXUIElement) -> [String] = AXAccessibility.actionNames
    ) -> AXNode {
        let role = stringAttribute(element, AXAttribute.role) ?? "unknown"
        let subrole = stringAttribute(element, AXAttribute.subrole) ?? ""
        let secure = isSecureValue(role: role, subrole: subrole)

        // Never even retrieve secure text. Some apps repeat it in the title or
        // description, so all three serialized text fields must be redacted.
        let value = secure ? "[REDACTED]" : stringAttribute(element, AXAttribute.value)
        let description = secure ? "[REDACTED]" : stringAttribute(element, AXAttribute.description)
        let name = secure ? "[REDACTED]" : (stringAttribute(element, AXAttribute.title) ?? description)

        let frame = frameAttribute(element)
        return AXNode(
            role: role,
            name: name,
            value: value,
            description: description,
            enabled: boolAttribute(element, AXAttribute.enabled),
            focused: boolAttribute(element, AXAttribute.focused),
            selected: boolAttribute(element, AXAttribute.selected),
            secure: secure,
            actions: actionNames(element),
            frame: frame,
            target: TargetDescriptor(pid: pid, role: role, name: name, path: path, frame: frame),
            depth: depth,
            source: "ax"
        )
    }

    private static func closestWindow(
        to frame: Rect,
        candidates: [AXUIElement]
    ) -> AXUIElement? {
        let ranked = candidates.compactMap { candidate -> (AXUIElement, Double)? in
            guard let candidateFrame = frameAttribute(candidate) else { return nil }
            let distance = abs(candidateFrame.x - frame.x)
                + abs(candidateFrame.y - frame.y)
                + abs(candidateFrame.width - frame.width)
                + abs(candidateFrame.height - frame.height)
            return (candidate, distance)
        }.sorted { $0.1 < $1.1 }
        guard let first = ranked.first, first.1 <= 32 else { return nil }
        if ranked.count > 1, ranked[1].1 - first.1 <= 4 { return nil }
        return first.0
    }

    /// Secure values (passwords, secure text fields) are never serialized.
    public static func isSecureValue(role: String, subrole: String) -> Bool {
        if role == AXRole.secureTextField { return true }
        if role == AXRole.textField && subrole == AXRole.secureTextField { return true }
        let lowerRole = role.lowercased()
        let lowerSub = subrole.lowercased()
        return lowerRole.contains("password")
            || lowerRole.contains("secure")
            || lowerSub.contains("secure")
    }
}
