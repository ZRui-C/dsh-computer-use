import Foundation

/// Installation belongs to one Host profile. Never infer Desktop from a web install.
public enum DSHInstallationTarget: String, CaseIterable, Sendable {
    case web
    case desktop

    public var executablePreferenceKey: String {
        self == .web ? "dshExecutable" : "desktopDSHExecutable"
    }

    public func manifestURL(dshHome: URL) -> URL {
        dshHome.appendingPathComponent("profiles/\(rawValue)/package.json")
    }

    public func installArguments(pluginDirectory: URL) -> [String] {
        ["plugin", "--profile", rawValue, "add", "--save-exact", "file:\(pluginDirectory.path)"]
    }

    public static func desktopLauncher(in application: URL) -> URL {
        application.appendingPathComponent("Contents/Resources/runtime/cli/bin/dsh")
    }

    /// Resolve an app selection or a symlink to its bundled command. Ordinary npm
    /// launchers cannot mutate Electron's managed profile and must not be used.
    public static func desktopApplication(for selection: URL) -> URL? {
        let resolved = selection.resolvingSymlinksInPath().standardizedFileURL
        if resolved.pathExtension == "app" { return resolved }
        let suffix = "/Contents/Resources/runtime/cli/bin/dsh"
        guard resolved.path.hasSuffix(suffix) else { return nil }
        let application = URL(fileURLWithPath: String(resolved.path.dropLast(suffix.count)))
        guard application.pathExtension == "app" else { return nil }
        return application
    }
}
