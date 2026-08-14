import Foundation
import CoreGraphics

public enum MouseButton: String, Codable, Equatable {
    case left
    case right
    case center

    public var cgMouseButton: CGMouseButton {
        switch self {
        case .left: return .left
        case .right: return .right
        case .center: return .center
        }
    }
}

/// A serializable AX target plus process/window identity for background input.
public struct TargetDescriptor: Codable, Equatable, Hashable {
    public var bundleId: String?
    public var pid: Int32?
    public var windowId: UInt32?
    public var windowFrame: Rect?
    public var role: String?
    public var name: String?
    public var identifier: String?
    public var path: [Int]?
    public var frame: Rect?
    public var ocrText: String?

    public init(
        bundleId: String? = nil,
        pid: Int32? = nil,
        windowId: UInt32? = nil,
        windowFrame: Rect? = nil,
        role: String? = nil,
        name: String? = nil,
        identifier: String? = nil,
        path: [Int]? = nil,
        frame: Rect? = nil,
        ocrText: String? = nil
    ) {
        self.bundleId = bundleId
        self.pid = pid
        self.windowId = windowId
        self.windowFrame = windowFrame
        self.role = role
        self.name = name
        self.identifier = identifier
        self.path = path
        self.frame = frame
        self.ocrText = ocrText
    }
}

/// A discriminated action carried by the native NDJSON protocol. Input cases
/// accept an optional target so the helper can route events to a background app.
public enum DesktopAction: Equatable {
    case launchApp(bundleId: String?, path: String?, appName: String?)
    case focus(target: TargetDescriptor?, background: Bool)
    case click(point: Point, button: MouseButton, count: Int, target: TargetDescriptor?)
    case doubleClick(point: Point, target: TargetDescriptor?)
    case hover(point: Point, target: TargetDescriptor?)
    case type(text: String, target: TargetDescriptor?)
    case press(keys: [String], target: TargetDescriptor?)
    case scroll(point: Point, deltaX: Double, deltaY: Double, target: TargetDescriptor?)
    case drag(from: Point, to: Point, button: MouseButton, duration: Double, target: TargetDescriptor?)
    case wait(milliseconds: Int)
    case axAction(action: String, target: TargetDescriptor?)
    case setValue(value: String, target: TargetDescriptor?)

    public var typeName: String {
        switch self {
        case .launchApp: return "launchApp"
        case .focus: return "focus"
        case .click: return "click"
        case .doubleClick: return "doubleClick"
        case .hover: return "hover"
        case .type: return "type"
        case .press: return "press"
        case .scroll: return "scroll"
        case .drag: return "drag"
        case .wait: return "wait"
        case .axAction: return "axAction"
        case .setValue: return "setValue"
        }
    }
}

extension DesktopAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, bundleId, path, appName, target, background, point, button, count, text
        case keys, deltaX, deltaY, from, to, duration, milliseconds
        case action, value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let target = try container.decodeIfPresent(TargetDescriptor.self, forKey: .target)
        switch type {
        case "launchApp":
            self = .launchApp(
                bundleId: try container.decodeIfPresent(String.self, forKey: .bundleId),
                path: try container.decodeIfPresent(String.self, forKey: .path),
                appName: try container.decodeIfPresent(String.self, forKey: .appName)
            )
        case "focus":
            self = .focus(
                target: target,
                background: try container.decodeIfPresent(Bool.self, forKey: .background) ?? false
            )
        case "click":
            self = .click(
                point: try container.decode(Point.self, forKey: .point),
                button: try container.decode(MouseButton.self, forKey: .button),
                count: try container.decodeIfPresent(Int.self, forKey: .count) ?? 1,
                target: target
            )
        case "doubleClick":
            self = .doubleClick(
                point: try container.decode(Point.self, forKey: .point),
                target: target
            )
        case "hover":
            self = .hover(
                point: try container.decode(Point.self, forKey: .point),
                target: target
            )
        case "type":
            self = .type(text: try container.decode(String.self, forKey: .text), target: target)
        case "press":
            self = .press(keys: try container.decode([String].self, forKey: .keys), target: target)
        case "scroll":
            self = .scroll(
                point: try container.decode(Point.self, forKey: .point),
                deltaX: try container.decodeIfPresent(Double.self, forKey: .deltaX) ?? 0,
                deltaY: try container.decodeIfPresent(Double.self, forKey: .deltaY) ?? 0,
                target: target
            )
        case "drag":
            self = .drag(
                from: try container.decode(Point.self, forKey: .from),
                to: try container.decode(Point.self, forKey: .to),
                button: try container.decode(MouseButton.self, forKey: .button),
                duration: try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0,
                target: target
            )
        case "wait":
            self = .wait(milliseconds: try container.decode(Int.self, forKey: .milliseconds))
        case "axAction":
            self = .axAction(
                action: try container.decode(String.self, forKey: .action),
                target: target
            )
        case "setValue":
            self = .setValue(
                value: try container.decode(String.self, forKey: .value),
                target: target
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown desktop action type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName, forKey: .type)
        switch self {
        case .launchApp(let bundleId, let path, let appName):
            try container.encodeIfPresent(bundleId, forKey: .bundleId)
            try container.encodeIfPresent(path, forKey: .path)
            try container.encodeIfPresent(appName, forKey: .appName)
        case .focus(let target, let background):
            try container.encodeIfPresent(target, forKey: .target)
            try container.encode(background, forKey: .background)
        case .click(let point, let button, let count, let target):
            try container.encode(point, forKey: .point)
            try container.encode(button, forKey: .button)
            try container.encode(count, forKey: .count)
            try container.encodeIfPresent(target, forKey: .target)
        case .doubleClick(let point, let target):
            try container.encode(point, forKey: .point)
            try container.encodeIfPresent(target, forKey: .target)
        case .hover(let point, let target):
            try container.encode(point, forKey: .point)
            try container.encodeIfPresent(target, forKey: .target)
        case .type(let text, let target):
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(target, forKey: .target)
        case .press(let keys, let target):
            try container.encode(keys, forKey: .keys)
            try container.encodeIfPresent(target, forKey: .target)
        case .scroll(let point, let deltaX, let deltaY, let target):
            try container.encode(point, forKey: .point)
            try container.encode(deltaX, forKey: .deltaX)
            try container.encode(deltaY, forKey: .deltaY)
            try container.encodeIfPresent(target, forKey: .target)
        case .drag(let from, let to, let button, let duration, let target):
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
            try container.encode(button, forKey: .button)
            try container.encode(duration, forKey: .duration)
            try container.encodeIfPresent(target, forKey: .target)
        case .wait(let milliseconds):
            try container.encode(milliseconds, forKey: .milliseconds)
        case .axAction(let action, let target):
            try container.encode(action, forKey: .action)
            try container.encodeIfPresent(target, forKey: .target)
        case .setValue(let value, let target):
            try container.encode(value, forKey: .value)
            try container.encodeIfPresent(target, forKey: .target)
        }
    }
}
