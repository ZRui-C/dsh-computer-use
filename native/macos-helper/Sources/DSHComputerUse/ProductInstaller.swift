import AppKit
import Foundation
import DSHComputerUseCore

struct ProductInstallState {
    let dshExecutable: String?
    let pluginInstalled: Bool
    let pluginNeedsRepair: Bool
}

struct ProductInstallResult {
    let succeeded: Bool
    let message: String
}

enum ProductInstaller {
    private static let packageName = "dsh-computer-use"

    static func inspect(target: DSHInstallationTarget = .web) -> ProductInstallState {
        let status = installedPluginStatus(target: target)
        return ProductInstallState(
            dshExecutable: findDSHExecutable(target: target),
            pluginInstalled: status == .active,
            pluginNeedsRepair: status == .dependencyOnly
        )
    }

    static func remember(dshExecutable: String, target: DSHInstallationTarget = .web) {
        UserDefaults.standard.set(dshExecutable, forKey: target.executablePreferenceKey)
    }

    static func install(dshExecutable explicitExecutable: String?, target: DSHInstallationTarget = .web) -> ProductInstallResult {
        let environment = ProcessInfo.processInfo.environment
        let appPath = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        if !appPath.hasPrefix("/Applications/"),
           environment["DSH_COMPUTER_USE_ALLOW_UNINSTALLED"] != "1" {
            return ProductInstallResult(
                succeeded: false,
                message: localized(
                    zh: "请先将 DSH Computer Use 拖入“应用程序”，重新打开后再安装插件。",
                    en: "Move DSH Computer Use to Applications, reopen it, then install the plugin."
                )
            )
        }
        guard var executable = explicitExecutable ?? findDSHExecutable(target: target) else {
            return ProductInstallResult(
                succeeded: false,
                message: localized(
                    zh: "未找到 dsh 命令。请先安装 DeepSeek Harness。",
                    en: "The dsh command was not found. Install DeepSeek Harness first."
                )
            )
        }
        if target == .desktop {
            guard let app = desktopApplication(for: executable) else {
                return ProductInstallResult(succeeded: false, message: localized(
                    zh: "请选择官方 DeepSeek Harness.app 或其内置 dsh 命令，不能使用 npm 安装的 dsh。",
                    en: "Choose the official DeepSeek Harness.app or its bundled dsh command, not npm-installed dsh."
                ))
            }
            guard FileManager.default.fileExists(atPath: target.manifestURL(dshHome: dshHome).path) else {
                return ProductInstallResult(succeeded: false, message: localized(
                    zh: "请先打开官方 DeepSeek Harness App 完成初始化，再完全退出 App 后重试。",
                    en: "Open the official DeepSeek Harness app once to initialize it, then fully quit it and retry."
                ))
            }
            executable = DSHInstallationTarget.desktopLauncher(in: app).path
            let identifier = Bundle(url: app)?.bundleIdentifier
            let running = NSWorkspace.shared.runningApplications.contains {
                $0.bundleURL?.resolvingSymlinksInPath() == app ||
                (identifier != nil && $0.bundleIdentifier == identifier)
            }
            guard !running else {
                return ProductInstallResult(succeeded: false, message: localized(
                    zh: "请先用 ⌘Q 完全退出 DeepSeek Harness App，再安装插件。关闭窗口并不等于退出。",
                    en: "Fully quit DeepSeek Harness with Command-Q before installing. Closing its window does not quit it."
                ))
            }
        }
        guard let pluginDirectory = Bundle.main.resourceURL?.appendingPathComponent("Plugin"),
              FileManager.default.fileExists(
                  atPath: pluginDirectory.appendingPathComponent("package.json").path
              ) else {
            return ProductInstallResult(
                succeeded: false,
                message: localized(
                    zh: "App 内缺少已编译插件资源，请重新下载安装包。",
                    en: "The compiled plugin is missing from this app. Download the installer again."
                )
            )
        }

        let process = Process()
        let output = Pipe()
        let arguments = target.installArguments(pluginDirectory: pluginDirectory)
        if target == .desktop {
            // The bundled shell launcher supplies Electron Node mode and pnpm.
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment.merging(["DSH_HOME": dshHome.path]) { _, new in new }
        } else {
            // Keep login-shell PATH discovery for npm/Homebrew installs. Values
            // are positional arguments, never interpolated into shell source.
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [
                "-lic", "exec \"$@\"",
                "dsh-computer-use-installer", executable,
            ] + arguments
        }
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus == 0 else {
                return ProductInstallResult(
                    succeeded: false,
                    message: text.isEmpty
                        ? localized(zh: "DSH 插件安装失败。", en: "DSH plugin installation failed.")
                        : text
                )
            }
            return ProductInstallResult(
                succeeded: true,
                message: localized(
                    zh: target == .desktop
                        ? "插件已在 desktop profile 启用。请重新打开官方 DeepSeek Harness App。"
                        : "插件已在 web profile 启用。请重启运行中的 Web Host 或 DSH for Mac 管理的 Host。",
                    en: target == .desktop
                        ? "Plugin enabled in the desktop profile. Reopen the official DeepSeek Harness app."
                        : "Plugin enabled in the web profile. Restart the Web Host or the Host managed by DSH for Mac."
                )
            )
        } catch {
            return ProductInstallResult(succeeded: false, message: error.localizedDescription)
        }
    }

    private static func findDSHExecutable(target: DSHInstallationTarget) -> String? {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if target == .desktop {
            let candidates = [
                environment["DSH_DESKTOP_EXECUTABLE"],
                UserDefaults.standard.string(forKey: target.executablePreferenceKey),
                "/Applications/DeepSeek Harness.app",
                "\(home)/Applications/DeepSeek Harness.app",
                "/usr/local/bin/dsh",
                "/opt/homebrew/bin/dsh",
            ]
            return candidates.compactMap { $0 }.compactMap { candidate in
                desktopApplication(for: candidate).map { DSHInstallationTarget.desktopLauncher(in: $0).path }
            }.first
        }
        let candidates = [
            environment["DSH_EXECUTABLE"],
            UserDefaults.standard.string(forKey: "dshExecutable"),
            "/opt/homebrew/bin/dsh",
            "/usr/local/bin/dsh",
            "\(home)/.local/bin/dsh",
            "\(home)/.pnpm/bin/dsh",
            "\(home)/dsh/node_modules/.bin/dsh",
        ]
        if let match = candidates.compactMap({ $0 }).first(where: isExecutable) {
            return URL(fileURLWithPath: match).resolvingSymlinksInPath().path
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "command -v dsh"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  isExecutable(path) else { return nil }
            return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        } catch {
            return nil
        }
    }

    static func desktopApplication(for selection: String) -> URL? {
        guard let app = DSHInstallationTarget.desktopApplication(for: URL(fileURLWithPath: selection)),
              isExecutable(DSHInstallationTarget.desktopLauncher(in: app).path),
              isExecutable(app.appendingPathComponent("Contents/MacOS/DeepSeek Harness").path) else { return nil }
        return app
    }

    private static var dshHome: URL {
        ProcessInfo.processInfo.environment["DSH_HOME"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh")
    }

    private static func installedPluginStatus(target: DSHInstallationTarget) -> DSHProfilePluginStatus {
        let manifest = target.manifestURL(dshHome: dshHome)
        guard let data = try? Data(contentsOf: manifest) else { return .missing }
        return DSHProfileManifestInspector.pluginStatus(in: data, packageName: packageName)
    }

    private static func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    private static func localized(zh: String, en: String) -> String {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? zh : en
    }
}
