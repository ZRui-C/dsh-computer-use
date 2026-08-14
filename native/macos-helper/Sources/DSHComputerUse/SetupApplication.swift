import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

@MainActor
enum SetupApplication {
    static func run() {
        let application = NSApplication.shared
        let delegate = SetupAppDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class SetupAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = SetupModel()
        let content = SetupView(model: model)
        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = "DSH Computer Use"
        window.setContentSize(NSSize(width: 760, height: 620))
        window.minSize = NSSize(width: 680, height: 560)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        installMainMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func installMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: Copy.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }
}

@MainActor
private final class SetupModel: ObservableObject {
    @Published var accessibilityGranted = false
    @Published var screenCaptureGranted = false
    @Published var dshExecutable: String?
    @Published var pluginInstalled = false
    @Published var pluginNeedsRepair = false
    @Published var isInstalling = false
    @Published var message: String?
    @Published var restartRequired = false

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let model = self else { return }
            Task { @MainActor in model.refreshPermissions() }
        }
    }

    deinit { timer?.invalidate() }

    var ready: Bool {
        accessibilityGranted && screenCaptureGranted && pluginInstalled
    }

    func refresh() {
        refreshPermissions()
        let state = ProductInstaller.inspect()
        dshExecutable = state.dshExecutable
        pluginInstalled = state.pluginInstalled
        pluginNeedsRepair = state.pluginNeedsRepair
    }

    func requestAccessibility() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacyPane("Privacy_Accessibility")
    }

    func requestScreenCapture() {
        _ = CGRequestScreenCaptureAccess()
        openPrivacyPane("Privacy_ScreenCapture")
    }

    func configurePlugin() {
        if dshExecutable == nil {
            let panel = NSOpenPanel()
            panel.title = Copy.chooseDSH
            panel.prompt = Copy.choose
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let path = panel.url?.path else { return }
            guard FileManager.default.isExecutableFile(atPath: path) else {
                message = Copy.notExecutable
                return
            }
            ProductInstaller.remember(dshExecutable: path)
            dshExecutable = path
        }
        installPlugin()
    }

    private func installPlugin() {
        guard !isInstalling else { return }
        isInstalling = true
        message = nil
        let executable = dshExecutable
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ProductInstaller.install(dshExecutable: executable)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isInstalling = false
                self.message = result.message
                self.restartRequired = result.succeeded
                self.refresh()
            }
        }
    }

    func openDSH() {
        guard let url = URL(string: "http://127.0.0.1:3080") else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 0) {
                SetupRow(
                    icon: "accessibility",
                    title: Copy.accessibilityTitle,
                    detail: Copy.accessibilityDetail,
                    complete: model.accessibilityGranted,
                    actionTitle: Copy.authorize,
                    action: model.requestAccessibility
                )
                Divider().padding(.leading, 64)
                SetupRow(
                    icon: "record.circle",
                    title: Copy.captureTitle,
                    detail: Copy.captureDetail,
                    complete: model.screenCaptureGranted,
                    actionTitle: Copy.authorize,
                    action: model.requestScreenCapture
                )
                Divider().padding(.leading, 64)
                SetupRow(
                    icon: "terminal",
                    title: Copy.dshTitle,
                    detail: dshDetail,
                    complete: model.pluginInstalled,
                    actionTitle: model.dshExecutable == nil
                        ? Copy.choose
                        : (model.pluginInstalled
                            ? Copy.reinstall
                            : (model.pluginNeedsRepair ? Copy.repair : Copy.install)),
                    busy: model.isInstalling,
                    action: model.configurePlugin
                )
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 14)

            if let message = model.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(model.pluginInstalled ? .secondary : Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)
            }

            Spacer(minLength: 12)
            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("DSH Computer Use")
                    .font(.system(size: 25, weight: .semibold))
                Text(Copy.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            StatusBadge(ready: model.ready)
            Button(action: model.refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(Copy.refresh)
            .accessibilityLabel(Copy.refresh)
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 22)
    }

    private var dshDetail: String {
        if model.pluginInstalled { return Copy.dshInstalled }
        if model.pluginNeedsRepair { return Copy.dshNeedsRepair }
        if let path = model.dshExecutable {
            return Copy.dshFound.replacingOccurrences(of: "%@", with: path)
        }
        return Copy.dshMissing
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.restartRequired ? Copy.restartRequired : Copy.securityNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Copy.version)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if model.pluginInstalled {
                Button(Copy.openDSH, action: model.openDSH)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
    }
}

private struct SetupRow: View {
    let icon: String
    let title: String
    let detail: String
    let complete: Bool
    let actionTitle: String
    var busy = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(complete ? Color.green : Color.secondary)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(title).font(.headline)
                    Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(complete ? Color.green : Color.secondary)
                        .accessibilityLabel(complete ? Copy.complete : Copy.pending)
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 16)
            if busy {
                ProgressView().controlSize(.small).frame(width: 88)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .frame(minWidth: 88)
            }
        }
        .frame(minHeight: 104)
    }
}

private struct StatusBadge: View {
    let ready: Bool

    var body: some View {
        Label(ready ? Copy.ready : Copy.setupNeeded, systemImage: ready ? "checkmark.circle.fill" : "wrench.and.screwdriver")
            .font(.callout.weight(.medium))
            .foregroundStyle(ready ? Color.green : Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }
}

private enum Copy {
    private static let chinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
    static let subtitle = chinese ? "后台控制 Chromium 与 macOS 窗口，不占用你的鼠标。" : "Background control for Chromium and macOS without taking your pointer."
    static let accessibilityTitle = chinese ? "辅助功能" : "Accessibility"
    static let accessibilityDetail = chinese ? "读取控件语义并向你选择的应用投递输入。" : "Reads control semantics and routes input to the app you selected."
    static let captureTitle = chinese ? "屏幕录制" : "Screen Recording"
    static let captureDetail = chinese ? "捕获窗口像素，用于 OCR 与动作后验证。" : "Captures window pixels for OCR and post-action verification."
    static let dshTitle = chinese ? "DSH 插件" : "DSH Plugin"
    static let dshMissing = chinese ? "未找到 dsh 命令。请先安装 DeepSeek Harness。" : "The dsh command was not found. Install DeepSeek Harness first."
    static let dshInstalled = chinese ? "插件已全局启用，所有 agent preset 均可使用。" : "The plugin is globally enabled for every agent preset."
    static let dshNeedsRepair = chinese ? "依赖已存在，但尚未启用全局 bundle；点击“修复”。" : "The dependency exists but its global bundle is disabled. Select Repair."
    static let dshFound = chinese ? "已找到 %@，可以安装插件。" : "Found %@ and ready to install."
    static let authorize = chinese ? "授权" : "Authorize"
    static let install = chinese ? "安装" : "Install"
    static let repair = chinese ? "修复" : "Repair"
    static let reinstall = chinese ? "重新安装" : "Reinstall"
    static let choose = chinese ? "选择…" : "Choose…"
    static let chooseDSH = chinese ? "选择 dsh 可执行文件" : "Choose the dsh executable"
    static let notExecutable = chinese ? "所选文件不可执行。" : "The selected file is not executable."
    static let openDSH = chinese ? "打开 DSH" : "Open DSH"
    static let ready = chinese ? "可以使用" : "Ready"
    static let setupNeeded = chinese ? "需要设置" : "Setup needed"
    static let refresh = chinese ? "刷新状态" : "Refresh status"
    static let complete = chinese ? "已完成" : "Complete"
    static let pending = chinese ? "待完成" : "Pending"
    static let restartRequired = chinese ? "插件已更新。请重启正在运行的 DSH Host。" : "Plugin updated. Restart the running DSH Host."
    static let securityNote = chinese ? "权限只在本机使用；后台输入优先锁定目标进程与窗口。" : "Permissions stay local; background input is pinned to the target process and window."
    static let quit = chinese ? "退出 DSH Computer Use" : "Quit DSH Computer Use"
    static var version: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return chinese ? "版本 \(value) · tech.zrui" : "Version \(value) · tech.zrui"
    }
}
