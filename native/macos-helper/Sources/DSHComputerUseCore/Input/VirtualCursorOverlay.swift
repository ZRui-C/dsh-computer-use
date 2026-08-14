import AppKit
import Foundation

/// A click-through software cursor used only for per-process background input.
/// It never becomes key/main and therefore does not replace the user's cursor.
final class VirtualCursorOverlay {
    static let shared = VirtualCursorOverlay()

    private let enabled = ProcessInfo.processInfo.environment["DEEPSEEK_VIRTUAL_CURSOR"] != "0"
    private var panel: NSPanel?
    private var cursorSize = CGSize(width: 28, height: 28)
    private var hotspot = CGPoint(x: 4, y: 4)

    private init() {}

    func show(at point: Point) {
        guard enabled else { return }
        DispatchQueue.main.async { [weak self] in
            self?.showOnMain(at: point.cgPoint)
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }

    private func showOnMain(at point: CGPoint) {
        let panel = panel ?? makePanel()
        let desktopMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let appKitPoint = CGPoint(x: point.x, y: desktopMaxY - point.y)
        panel.setFrameOrigin(CGPoint(
            x: appKitPoint.x - hotspot.x,
            y: appKitPoint.y - (cursorSize.height - hotspot.y)
        ))
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        _ = NSApplication.shared
        let cursor = NSCursor.arrow
        cursorSize = cursor.image.size
        hotspot = cursor.hotSpot

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: cursorSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let imageView = NSImageView(frame: CGRect(origin: .zero, size: cursorSize))
        imageView.image = cursor.image
        imageView.imageScaling = .scaleNone
        panel.contentView = imageView
        self.panel = panel
        return panel
    }
}
