import Foundation

/// Permission / session snapshot exposed by `status` and `observeDesktop`.
/// Field names map 1:1 to the TypeScript driver's `permissions` shape.
public struct PermissionsReport: Codable, Equatable {
    public var accessibility: Bool
    public var screenCapture: Bool
    public var aquaSession: Bool
    public var screenLocked: Bool

    public init(accessibility: Bool, screenCapture: Bool, aquaSession: Bool, screenLocked: Bool) {
        self.accessibility = accessibility
        self.screenCapture = screenCapture
        self.aquaSession = aquaSession
        self.screenLocked = screenLocked
    }
}

/// Result of the `handshake` method. `protocolVersion` is the integer wire
/// protocol version; `helperVersion` is the helper's own semver.
public struct HandshakeResult: Codable, Equatable {
    public var protocolVersion: Int
    public var helperVersion: String
    public var appName: String
    public var platform: String
    public var capabilities: [String]

    public init(
        protocolVersion: Int,
        helperVersion: String,
        appName: String,
        platform: String,
        capabilities: [String]
    ) {
        self.protocolVersion = protocolVersion
        self.helperVersion = helperVersion
        self.appName = appName
        self.platform = platform
        self.capabilities = capabilities
    }
}

/// Result of the `status` method.
public struct StatusReport: Codable, Equatable {
    public var permissions: PermissionsReport
    public var mainDisplayCount: Int
    public var socketPath: String?
    public var macosVersion: String
    public var architecture: String?

    public init(
        permissions: PermissionsReport,
        mainDisplayCount: Int,
        socketPath: String? = nil,
        macosVersion: String,
        architecture: String? = nil
    ) {
        self.permissions = permissions
        self.mainDisplayCount = mainDisplayCount
        self.socketPath = socketPath
        self.macosVersion = macosVersion
        self.architecture = architecture
    }
}

/// Result of a single `performDesktop` action.
public struct ActionResult: Codable, Equatable {
    public var performed: Bool
    public var action: String
    /// Which backend satisfied the action: `ax` or `coregraphics`.
    public var method: String?
    public var detail: String?

    public init(performed: Bool, action: String, method: String? = nil, detail: String? = nil) {
        self.performed = performed
        self.action = action
        self.method = method
        self.detail = detail
    }
}
