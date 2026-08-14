import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit

/// A captured frame plus the metadata needed to map image pixels into global
/// top-left points. Window metadata is present for desktop-independent capture.
public struct CapturedDisplay {
    public var image: CGImage
    public var origin: CGPoint
    public var scale: CGFloat
    public var pointSize: CGSize
    public var windowId: UInt32?
    public var pid: Int32?
    public var title: String?

    public init(
        image: CGImage,
        origin: CGPoint,
        scale: CGFloat,
        pointSize: CGSize,
        windowId: UInt32? = nil,
        pid: Int32? = nil,
        title: String? = nil
    ) {
        self.image = image
        self.origin = origin
        self.scale = scale
        self.pointSize = pointSize
        self.windowId = windowId
        self.pid = pid
        self.title = title
    }
}

struct CaptureWindowCandidate: Equatable {
    var windowId: UInt32
    var pid: Int32
    var title: String?
    var frame: Rect
    var isOnScreen: Bool
    var layer: Int
}

/// Screen capture backed by ScreenCaptureKit one-shot screenshots.
public final class ScreenCaptureManager {
    public init() {}

    public func captureInfo() -> (preflight: Bool, available: Bool, mainDisplayCount: Int) {
        let preflight = Permissions.screenCapturePreflight
        let count = preflight ? shareableDisplayCount() : 0
        return (preflight, preflight && count > 0, count)
    }

    public func captureMainDisplay() throws -> CapturedDisplay {
        let displayID = CGMainDisplayID()
        let bounds = CGDisplayBounds(displayID)
        let pixelWidth = CGDisplayPixelsWide(displayID)
        let pixelHeight = CGDisplayPixelsHigh(displayID)
        let scale = CGFloat(pixelWidth) / max(bounds.width, 1)

        return try runAsyncCapture {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw AgentError.input("Main display not found in shareable content")
            }
            let configuration = SCStreamConfiguration()
            configuration.width = pixelWidth
            configuration.height = pixelHeight
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingWindows: []),
                configuration: configuration
            )
            return CapturedDisplay(
                image: image,
                origin: bounds.origin,
                scale: scale,
                pointSize: bounds.size
            )
        }
    }

    /// Captures one process-owned window independently of the desktop. Window ID
    /// wins, followed by title/frame correlation and a deterministic PID-only
    /// fallback.
    public func captureWindow(
        target: TargetDescriptor,
        fallbackTitle: String? = nil,
        fallbackFrame: Rect? = nil
    ) throws -> CapturedDisplay {
        guard let pid = target.pid else {
            throw AgentError.invalidParams("Window capture requires a target pid")
        }

        do {
            return try runAsyncCapture {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
                let processWindows = content.windows.filter {
                    $0.owningApplication?.processID == pid && $0.frame.width > 0 && $0.frame.height > 0
                }
                guard let window = self.selectWindow(
                    processWindows,
                    target: target,
                    fallbackTitle: fallbackTitle,
                    fallbackFrame: fallbackFrame
                ) else {
                    throw AgentError.input("No unambiguous ScreenCaptureKit window found for pid \(pid)")
                }
                if let fallbackFrame,
                   self.isStageManagerThumbnail(window.frame, expected: fallbackFrame.cgRect) {
                    throw AgentError.input(
                        "Stage Manager exposes the target only as a shelf thumbnail; AX observation remains available"
                    )
                }

                let filter = SCContentFilter(desktopIndependentWindow: window)
                let filterRect = filter.contentRect
                let contentSize = filterRect.width > 0 && filterRect.height > 0
                    ? filterRect.size
                    : (fallbackFrame?.cgRect.size ?? window.frame.size)
                let scale = filter.pointPixelScale > 0
                    ? CGFloat(filter.pointPixelScale)
                    : self.displayScale(for: fallbackFrame?.cgRect ?? window.frame)
                let configuration = SCStreamConfiguration()
                configuration.width = max(1, Int((contentSize.width * scale).rounded()))
                configuration.height = max(1, Int((contentSize.height * scale).rounded()))
                configuration.showsCursor = false
                configuration.shouldBeOpaque = false
                configuration.ignoreShadowsSingleWindow = true

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                guard self.imageHasVisibleContent(image) else {
                    throw AgentError.input("ScreenCaptureKit returned a blank window image")
                }
                let coordinateFrame = fallbackFrame?.cgRect
                    ?? CGRect(origin: window.frame.origin, size: contentSize)
                return CapturedDisplay(
                    image: image,
                    origin: coordinateFrame.origin,
                    scale: CGFloat(image.width) / max(coordinateFrame.width, 1),
                    pointSize: coordinateFrame.size,
                    windowId: window.windowID,
                    pid: pid,
                    title: window.title ?? fallbackTitle
                )
            }
        } catch {
            if let agentError = error as? AgentError,
               agentError.message.hasPrefix("Stage Manager exposes") {
                throw agentError
            }
            guard let windowId = target.windowId else { throw error }
            return try captureWindowWithScreenshotCommand(
                windowId: windowId,
                pid: pid,
                title: fallbackTitle,
                frame: fallbackFrame,
                nativeError: error
            )
        }
    }

    public func writePNG(_ image: CGImage, to path: String) throws {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw AgentError.input("Failed to encode PNG for \(path)")
        }
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: url)
    }

    static func selectCandidate(
        _ candidates: [CaptureWindowCandidate],
        target: TargetDescriptor,
        fallbackTitle: String? = nil,
        fallbackFrame: Rect? = nil
    ) -> CaptureWindowCandidate? {
        let processCandidates = candidates.filter { candidate in
            target.pid == nil || candidate.pid == target.pid
        }
        if let windowId = target.windowId {
            return processCandidates.first(where: { $0.windowId == windowId })
        }

        let requestedTitle = target.role == "AXWindow" ? target.name : fallbackTitle
        if let requestedTitle, !requestedTitle.isEmpty {
            let exact = processCandidates.filter { $0.title == requestedTitle }
            if exact.count == 1 { return exact[0] }
        }

        let requestedFrame = fallbackFrame ?? (target.role == "AXWindow" ? target.frame : nil)
        if let requestedFrame {
            let sorted = processCandidates
                .map { ($0, frameDistance($0.frame, requestedFrame)) }
                .sorted { $0.1 < $1.1 }
            if let first = sorted.first, first.1 <= 32,
               sorted.count == 1 || sorted[1].1 - first.1 > 4 {
                return first.0
            }
        }

        let normalWindows = processCandidates.filter { $0.layer == 0 }
        let visible = normalWindows.filter(\.isOnScreen)
        if visible.count == 1 { return visible[0] }
        if normalWindows.count == 1 { return normalWindows[0] }
        return nil
    }

    private func selectWindow(
        _ windows: [SCWindow],
        target: TargetDescriptor,
        fallbackTitle: String?,
        fallbackFrame: Rect?
    ) -> SCWindow? {
        let candidates = windows.map {
            CaptureWindowCandidate(
                windowId: $0.windowID,
                pid: $0.owningApplication?.processID ?? 0,
                title: $0.title,
                frame: Rect($0.frame),
                isOnScreen: $0.isOnScreen,
                layer: $0.windowLayer
            )
        }
        guard let selected = Self.selectCandidate(
            candidates,
            target: target,
            fallbackTitle: fallbackTitle,
            fallbackFrame: fallbackFrame
        ) else {
            return nil
        }
        return windows.first(where: { $0.windowID == selected.windowId })
    }

    private func runAsyncCapture<T>(_ body: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var boxed: Result<T, Error>?
        Task {
            do { boxed = .success(try await body()) }
            catch { boxed = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return try boxed!.get()
    }

    private func shareableDisplayCount() -> Int {
        (try? runAsyncCapture {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            return content.displays.count
        }) ?? 0
    }

    private func captureWindowWithScreenshotCommand(
        windowId: UInt32,
        pid: Int32,
        title: String?,
        frame: Rect?,
        nativeError: Error
    ) throws -> CapturedDisplay {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deepseek-window-capture-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("window.png")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let process = Process()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-l", String(windowId), "-x", "-o", file.path]
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let image = NSImage(contentsOf: file) else {
            let message = String(
                data: standardError.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw AgentError.input(
                "Window capture failed; native: \(nativeError.localizedDescription); screencapture: \(message)"
            )
        }
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ), imageHasVisibleContent(cgImage) else {
            throw AgentError.input(
                "Window capture failed; native: \(nativeError.localizedDescription); screencapture returned a blank image"
            )
        }
        let captureFrame = frame?.cgRect
            ?? CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        return CapturedDisplay(
            image: cgImage,
            origin: captureFrame.origin,
            scale: CGFloat(cgImage.width) / max(captureFrame.width, 1),
            pointSize: captureFrame.size,
            windowId: windowId,
            pid: pid,
            title: title
        )
    }

    private func displayScale(for windowFrame: CGRect) -> CGFloat {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return 2
        }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
            return 2
        }
        let best = displayIDs.max { lhs, rhs in
            intersectionArea(CGDisplayBounds(lhs), windowFrame) < intersectionArea(CGDisplayBounds(rhs), windowFrame)
        } ?? CGMainDisplayID()
        return CGFloat(CGDisplayPixelsWide(best)) / max(CGDisplayBounds(best).width, 1)
    }

    private func imageHasVisibleContent(_ image: CGImage) -> Bool {
        guard image.bitsPerPixel >= 24,
              let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return false
        }
        let bytesPerPixel = max(3, image.bitsPerPixel / 8)
        let length = CFDataGetLength(data)
        guard length >= bytesPerPixel else { return false }
        let colorOffset: Int
        switch image.alphaInfo {
        case .premultipliedFirst, .first, .noneSkipFirst:
            colorOffset = 1
        default:
            colorOffset = 0
        }
        let pixelStep = max(1, (image.width * image.height) / 4_096)
        var pixel = 0
        let pixelCount = min(image.width * image.height, length / bytesPerPixel)
        while pixel < pixelCount {
            let base = pixel * bytesPerPixel + colorOffset
            let colorEnd = min(base + 3, min((pixel + 1) * bytesPerPixel, length))
            for index in base..<colorEnd where bytes[index] > 8 {
                return true
            }
            pixel += pixelStep
        }
        return false
    }

    private func isStageManagerThumbnail(_ frame: CGRect, expected: CGRect) -> Bool {
        frame.width < expected.width * 0.5 || frame.height < expected.height * 0.5
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func frameDistance(_ lhs: Rect, _ rhs: Rect) -> Double {
        abs(lhs.x - rhs.x)
            + abs(lhs.y - rhs.y)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }
}
