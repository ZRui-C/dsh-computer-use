import Foundation

struct ProductInstallState {
    let dshExecutable: String?
    let pluginInstalled: Bool
}

struct ProductInstallResult {
    let succeeded: Bool
    let message: String
}

enum ProductInstaller {
    private static let packageName = "dsh-computer-use"

    static func inspect() -> ProductInstallState {
        ProductInstallState(
            dshExecutable: findDSHExecutable(),
            pluginInstalled: installedPluginVersion() != nil
        )
    }

    static func remember(dshExecutable: String) {
        UserDefaults.standard.set(dshExecutable, forKey: "dshExecutable")
    }

    static func install(dshExecutable explicitExecutable: String?) -> ProductInstallResult {
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
        guard let executable = explicitExecutable ?? findDSHExecutable() else {
            return ProductInstallResult(
                succeeded: false,
                message: localized(
                    zh: "未找到 dsh 命令。请先安装 DeepSeek Harness。",
                    en: "The dsh command was not found. Install DeepSeek Harness first."
                )
            )
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
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-lic",
            "exec \"$1\" plugin --profile web add --save-exact \"file:$2\"",
            "dsh-computer-use-installer",
            executable,
            pluginDirectory.path,
        ]
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
                    zh: "DSH 插件已安装。重启正在运行的 DSH Host 后生效。",
                    en: "DSH plugin installed. Restart the running DSH Host to load it."
                )
            )
        } catch {
            return ProductInstallResult(succeeded: false, message: error.localizedDescription)
        }
    }

    private static func findDSHExecutable() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
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

    private static func installedPluginVersion() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let home = environment["DSH_HOME"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh")
        let manifest = home
            .appendingPathComponent("profiles/web/package.json")
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dependencies = object["dependencies"] as? [String: Any],
              let version = dependencies[packageName] as? String else {
            return nil
        }
        return version
    }

    private static func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    private static func localized(zh: String, en: String) -> String {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? zh : en
    }
}
