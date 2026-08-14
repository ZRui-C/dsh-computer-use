import Foundation
import CoreGraphics

/// A single observed node with a flat, serializable shape. `depth` is the AX
/// tree depth of the node (0 = the focused window root) and `source` is `"ax"`
/// or `"ocr"`.
public struct AXNode: Codable, Equatable {
    public var role: String
    public var name: String?
    public var value: String?
    public var description: String?
    public var enabled: Bool?
    public var focused: Bool?
    public var selected: Bool?
    public var secure: Bool
    public var actions: [String]
    public var frame: Rect?
    public var target: TargetDescriptor?
    public var depth: Int
    public var source: String

    public init(
        role: String,
        name: String? = nil,
        value: String? = nil,
        description: String? = nil,
        enabled: Bool? = nil,
        focused: Bool? = nil,
        selected: Bool? = nil,
        secure: Bool = false,
        actions: [String] = [],
        frame: Rect? = nil,
        target: TargetDescriptor? = nil,
        depth: Int = 0,
        source: String = "ax"
    ) {
        self.role = role
        self.name = name
        self.value = value
        self.description = description
        self.enabled = enabled
        self.focused = focused
        self.selected = selected
        self.secure = secure
        self.actions = actions
        self.frame = frame
        self.target = target
        self.depth = depth
        self.source = source
    }

    /// Whether this node already represents the given text (used to dedup OCR
    /// nodes against AX nodes by name/value).
    public func textMatches(_ text: String) -> Bool {
        let target = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return false }
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !name.isEmpty, name == target {
            return true
        }
        if let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !value.isEmpty, value == target {
            return true
        }
        return false
    }
}

/// Metadata about the frontmost running application.
public struct AppInfo: Codable, Equatable {
    public var bundleId: String?
    public var name: String?
    public var pid: Int32
    public var path: String?

    public init(bundleId: String? = nil, name: String? = nil, pid: Int32, path: String? = nil) {
        self.bundleId = bundleId
        self.name = name
        self.pid = pid
        self.path = path
    }
}

/// Metadata about a window (title, role, frame in global top-left points).
public struct WindowInfo: Codable, Equatable {
    public var title: String?
    public var role: String?
    public var frame: Rect?
    public var windowId: UInt32?

    public init(
        title: String? = nil,
        role: String? = nil,
        frame: Rect? = nil,
        windowId: UInt32? = nil
    ) {
        self.title = title
        self.role = role
        self.frame = frame
        self.windowId = windowId
    }
}

/// Metadata about a display (frame in global top-left points).
public struct DisplayInfo: Codable, Equatable {
    public var frame: Rect
    public var isMain: Bool

    public init(frame: Rect, isMain: Bool) {
        self.frame = frame
        self.isMain = isMain
    }
}

/// OCR mode selector for `observeDesktop`.
public enum OCRMode: String, Codable, Equatable {
    case auto
    case always
    case never
}

/// Parameters for the `observeDesktop` method.
public struct ObserveParams: Codable, Equatable {
    public var maxNodes: Int?
    public var ocr: OCRMode?
    public var screenshotPath: String?
    public var target: TargetDescriptor?

    public init(
        maxNodes: Int? = nil,
        ocr: OCRMode? = nil,
        screenshotPath: String? = nil,
        target: TargetDescriptor? = nil
    ) {
        self.maxNodes = maxNodes
        self.ocr = ocr
        self.screenshotPath = screenshotPath
        self.target = target
    }
}

/// The result of a desktop observation: frontmost app/window + display
/// metadata, a permissions snapshot, warnings, an optional screenshot path, and
/// a flat list of nodes (AX and OCR, deduped where practical).
public struct DesktopObservation: Codable, Equatable {
    public var timestamp: Double
    public var frontmostApp: AppInfo?
    public var frontmostWindow: WindowInfo?
    public var mainDisplay: DisplayInfo?
    public var displays: [DisplayInfo]
    public var permissions: PermissionsReport
    public var warnings: [String]
    public var screenshotPath: String?
    public var nodes: [AXNode]

    public init(
        timestamp: Double,
        frontmostApp: AppInfo? = nil,
        frontmostWindow: WindowInfo? = nil,
        mainDisplay: DisplayInfo? = nil,
        displays: [DisplayInfo] = [],
        permissions: PermissionsReport,
        warnings: [String] = [],
        screenshotPath: String? = nil,
        nodes: [AXNode] = []
    ) {
        self.timestamp = timestamp
        self.frontmostApp = frontmostApp
        self.frontmostWindow = frontmostWindow
        self.mainDisplay = mainDisplay
        self.displays = displays
        self.permissions = permissions
        self.warnings = warnings
        self.screenshotPath = screenshotPath
        self.nodes = nodes
    }
}
