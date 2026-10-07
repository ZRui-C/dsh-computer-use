import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// Observes either the requested process/window or, when no target is supplied,
/// the current frontmost app. OCR is derived from the selected window whenever
/// ScreenCaptureKit can resolve it.
public final class DesktopObserver {
    public static let maxDepth = AXAccessibility.defaultMaxDepth
    public static let defaultMaxNodes = 200

    private let screenCapture = ScreenCaptureManager()
    private let ocr = VisionOCRService()

    public init() {}

    public func observe(params: ObserveParams = ObserveParams()) -> DesktopObservation {
        let timestamp = Date().timeIntervalSince1970
        let permissions = Permissions.report
        let maxNodes = min(AXAccessibility.maximumNodes, max(1, params.maxNodes ?? Self.defaultMaxNodes))
        let ocrMode = params.ocr ?? .auto

        var appInfo: AppInfo?
        var windowInfo: WindowInfo?
        var nodes: [AXNode] = []
        var truncated = false
        var warnings: [String] = []
        var screenshotPath: String?

        let runningApp: NSRunningApplication?
        if let pid = params.target?.pid {
            runningApp = NSRunningApplication(processIdentifier: pid)
            if runningApp == nil {
                warnings.append("Requested target process \(pid) is not running")
            }
        } else {
            runningApp = NSWorkspace.shared.frontmostApplication
        }

        if let app = runningApp {
            let pid = app.processIdentifier
            appInfo = AppInfo(
                bundleId: app.bundleIdentifier,
                name: app.localizedName,
                pid: pid,
                path: app.bundleURL?.path
            )

            if permissions.accessibility {
                let axApp = AXAccessibility.application(pid: pid)
                AXAccessibility.prepare(axApp)
                windowInfo = self.windowInfo(for: axApp, target: params.target)
                let observation = AXAccessibility.observeWithDiagnostics(
                    app: axApp,
                    pid: pid,
                    target: params.target,
                    maxDepth: Self.maxDepth,
                    maxNodes: maxNodes
                )
                nodes = observation.nodes
                truncated = observation.hitDepthLimit || observation.hitNodeLimit
                if observation.hitDepthLimit { warnings.append("Accessibility tree reached depth limit \(Self.maxDepth)") }
                if observation.hitNodeLimit { warnings.append("Accessibility tree reached node limit \(maxNodes)") }
                if nodes.isEmpty {
                    warnings.append("Accessibility granted but no AX window tree was captured")
                }
            } else {
                warnings.append("Accessibility permission not granted; AX nodes unavailable")
            }
        }

        if ocrMode != .never {
            let shouldCapture = ocrMode == .always
                || (permissions.screenCapture && permissions.aquaSession && !permissions.screenLocked)
            if shouldCapture {
                do {
                    let captured = try captureTarget(
                        appInfo: appInfo,
                        windowInfo: windowInfo,
                        requestedTarget: params.target
                    )
                    if let requestedPath = params.screenshotPath {
                        try? screenCapture.writePNG(captured.image, to: requestedPath)
                        if FileManager.default.fileExists(atPath: requestedPath) {
                            screenshotPath = requestedPath
                        } else {
                            warnings.append("Screenshot write failed for \(requestedPath)")
                        }
                    }

                    if let windowId = captured.windowId {
                        windowInfo = WindowInfo(
                            title: captured.title ?? windowInfo?.title,
                            role: windowInfo?.role ?? AXRole.window,
                            frame: Rect(CGRect(origin: captured.origin, size: captured.pointSize)),
                            windowId: windowId
                        )
                        attachWindowIdentity(
                            windowId: windowId,
                            windowFrame: Rect(CGRect(origin: captured.origin, size: captured.pointSize)),
                            bundleId: appInfo?.bundleId,
                            nodes: &nodes
                        )
                    }

                    let observations = recognizeText(captured.image, languages: params.ocrLanguages ?? [], warnings: &warnings)
                    if observations.isEmpty {
                        warnings.append("OCR produced no text")
                    }
                    nodes.append(contentsOf: NodeMerger.ocrNodes(
                        from: observations,
                        origin: captured.origin,
                        scale: captured.scale,
                        existingAXNodes: nodes,
                        depth: 0
                    ))
                } catch {
                    warnings.append("Window capture failed: \(error.localizedDescription)")
                    if params.target == nil {
                        captureDisplayFallback(
                            params: params,
                            existingNodes: &nodes,
                            warnings: &warnings,
                            screenshotPath: &screenshotPath
                        )
                    }
                }
            } else if ocrMode == .always {
                warnings.append("Screen capture skipped: no capture permission, session, or screen is locked")
            }
        }

        if nodes.count > maxNodes {
            nodes = Array(nodes.prefix(maxNodes))
            truncated = true
            warnings.append("Combined AX/OCR observation reached node limit \(maxNodes)")
        }
        let displays = displayList()
        return DesktopObservation(
            timestamp: timestamp,
            frontmostApp: appInfo,
            frontmostWindow: windowInfo,
            mainDisplay: displays.first(where: { $0.isMain }),
            displays: displays,
            permissions: permissions,
            warnings: warnings,
            screenshotPath: screenshotPath,
            nodes: nodes,
            truncated: truncated
        )
    }

    private func recognizeText(_ image: CGImage, languages: [String], warnings: inout [String]) -> [OCRTextObservation] {
        do {
            return try ocr.recognize(cgImage: image, languages: languages)
        } catch {
            warnings.append("OCR failed: \(error.localizedDescription)")
            return []
        }
    }

    private func captureTarget(
        appInfo: AppInfo?,
        windowInfo: WindowInfo?,
        requestedTarget: TargetDescriptor?
    ) throws -> CapturedDisplay {
        guard let appInfo else { return try screenCapture.captureMainDisplay() }
        let target = TargetDescriptor(
            bundleId: appInfo.bundleId,
            pid: appInfo.pid,
            windowId: requestedTarget?.windowId ?? windowInfo?.windowId,
            role: AXRole.window,
            name: windowInfo?.title ?? (requestedTarget?.role == AXRole.window ? requestedTarget?.name : nil),
            frame: windowInfo?.frame
        )
        return try screenCapture.captureWindow(
            target: target,
            fallbackTitle: windowInfo?.title,
            fallbackFrame: windowInfo?.frame
        )
    }

    private func captureDisplayFallback(
        params: ObserveParams,
        existingNodes: inout [AXNode],
        warnings: inout [String],
        screenshotPath: inout String?
    ) {
        do {
            let captured = try screenCapture.captureMainDisplay()
            if let requestedPath = params.screenshotPath {
                try? screenCapture.writePNG(captured.image, to: requestedPath)
                if FileManager.default.fileExists(atPath: requestedPath) {
                    screenshotPath = requestedPath
                }
            }
            let observations = recognizeText(captured.image, languages: params.ocrLanguages ?? [], warnings: &warnings)
            existingNodes.append(contentsOf: NodeMerger.ocrNodes(
                from: observations,
                origin: captured.origin,
                scale: captured.scale,
                existingAXNodes: existingNodes,
                depth: 0
            ))
            warnings.append("Used main-display capture fallback")
        } catch {
            warnings.append("Screen capture fallback failed: \(error.localizedDescription)")
        }
    }

    private func attachWindowIdentity(
        windowId: UInt32,
        windowFrame: Rect,
        bundleId: String?,
        nodes: inout [AXNode]
    ) {
        for index in nodes.indices {
            nodes[index].target?.windowId = windowId
            nodes[index].target?.windowFrame = windowFrame
            nodes[index].target?.bundleId = bundleId
        }
    }

    private func windowInfo(for app: AXUIElement, target: TargetDescriptor?) -> WindowInfo? {
        guard let window = AXAccessibility.window(app, matching: target) else { return nil }
        return WindowInfo(
            title: AXAccessibility.stringAttribute(window, AXAttribute.title),
            role: AXAccessibility.stringAttribute(window, AXAttribute.role),
            frame: AXAccessibility.frameAttribute(window)
        )
    }

    private func displayList() -> [DisplayInfo] {
        let screens = NSScreen.screens
        let unionMaxY = screens.map(\.frame.maxY).max() ?? 0
        let main = NSScreen.main
        return screens.map { screen in
            let flipped = Geometry.flipVertical(screen.frame, containerHeight: unionMaxY)
            return DisplayInfo(frame: Rect(flipped), isMain: screen == main)
        }
    }
}
