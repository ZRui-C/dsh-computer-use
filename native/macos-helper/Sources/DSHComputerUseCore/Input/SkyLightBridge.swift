import AppKit
import CoreGraphics
import Darwin
import Foundation

struct SkyLightSyntheticFocusContext {
    let targetPSN: [UInt8]
    let windowId: UInt32
}

private typealias SLEventPostToPidFunction = @convention(c) (
    pid_t,
    UnsafeMutableRawPointer?
) -> Void
private typealias SLEventSetIntegerValueFieldFunction = @convention(c) (
    UnsafeMutableRawPointer?,
    UInt32,
    Int64
) -> Void
private typealias CGEventSetWindowLocationFunction = @convention(c) (
    UnsafeMutableRawPointer?,
    Double,
    Double
) -> Void
private typealias SLPSPostEventRecordToFunction = @convention(c) (
    UnsafeRawPointer?,
    UnsafePointer<UInt8>?
) -> Int32
private typealias GetProcessForPIDFunction = @convention(c) (
    pid_t,
    UnsafeMutableRawPointer?
) -> Int32

/// Runtime-only bridge around the private WindowServer functions used by the
/// targeted click path. Undocumented ABI is contained in this file so a macOS
/// compatibility change has one review boundary.
enum SkyLightBridge {
    private static let symbols = Symbols.load()

    static var canPostToProcess: Bool { symbols.postEventToPid != nil }
    static var canFocusWithoutRaise: Bool {
        symbols.postEventRecord != nil && symbols.getProcessForPID != nil
    }
    static var canBackgroundClick: Bool {
        symbols.postEventToPid != nil
            && symbols.setIntegerField != nil
            && symbols.setWindowLocation != nil
            && symbols.postEventRecord != nil
            && symbols.getProcessForPID != nil
    }

    static func isRoutableGUIProcess(_ pid: pid_t) -> Bool {
        guard pid > 0, kill(pid, 0) == 0,
              let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        return app.activationPolicy != .prohibited
    }

    @discardableResult
    static func post(_ event: CGEvent, to pid: pid_t) -> Bool {
        guard isRoutableGUIProcess(pid), let post = symbols.postEventToPid else {
            return false
        }
        post(pid, opaquePointer(for: event))
        return true
    }

    @discardableResult
    static func stampMouseEvent(
        _ event: CGEvent,
        pid: pid_t,
        windowId: UInt32,
        windowPoint: CGPoint,
        clickState: Int64,
        phase: Int64,
        clickGroupId: Int64
    ) -> Bool {
        guard let setInteger = symbols.setIntegerField,
              let setLocation = symbols.setWindowLocation else {
            return false
        }
        let pointer = opaquePointer(for: event)
        let window = Int64(windowId)
        setInteger(pointer, 0, phase)
        setInteger(pointer, 1, clickState)
        setInteger(pointer, 3, 0)
        setInteger(pointer, 7, 3)
        setInteger(pointer, 40, Int64(pid))
        setInteger(pointer, 51, window)
        setInteger(pointer, 58, clickGroupId)
        setInteger(pointer, 91, window)
        setInteger(pointer, 92, window)
        setLocation(pointer, windowPoint.x, windowPoint.y)
        return true
    }

    static func beginSyntheticTargetFocus(
        pid: pid_t,
        windowId: UInt32
    ) -> SkyLightSyntheticFocusContext? {
        guard canFocusWithoutRaise,
              isRoutableGUIProcess(pid),
              windowIsOnScreen(windowId, ownedBy: pid),
              let getProcess = symbols.getProcessForPID else {
            return nil
        }

        var psn = [UInt8](repeating: 0, count: 8)
        let status = psn.withUnsafeMutableBytes { bytes in
            getProcess(pid, bytes.baseAddress)
        }
        guard status == 0,
              postActivation(psn: psn, windowId: windowId, focused: true) else {
            return nil
        }
        Thread.sleep(forTimeInterval: 0.040)
        return SkyLightSyntheticFocusContext(targetPSN: psn, windowId: windowId)
    }

    @discardableResult
    static func endSyntheticTargetFocus(_ context: SkyLightSyntheticFocusContext) -> Bool {
        let result = postActivation(
            psn: context.targetPSN,
            windowId: context.windowId,
            focused: false
        )
        Thread.sleep(forTimeInterval: 0.040)
        return result
    }

    static func windowIsOnScreen(_ windowId: UInt32, ownedBy pid: pid_t) -> Bool {
        let info = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            CGWindowID(windowId)
        ) as? [[String: Any]] ?? []
        return info.contains { entry in
            guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                  number.uint32Value == windowId,
                  let owner = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == pid,
                  let onScreen = entry[kCGWindowIsOnscreen as String] as? NSNumber else {
                return false
            }
            return onScreen.boolValue
        }
    }

    private static func postActivation(
        psn: [UInt8],
        windowId: UInt32,
        focused: Bool
    ) -> Bool {
        guard let post = symbols.postEventRecord else { return false }
        var record = [UInt8](repeating: 0, count: 0xF8)
        record[0x04] = 0xF8
        record[0x08] = 0x0D
        record[0x3C] = UInt8(truncatingIfNeeded: windowId)
        record[0x3D] = UInt8(truncatingIfNeeded: windowId >> 8)
        record[0x3E] = UInt8(truncatingIfNeeded: windowId >> 16)
        record[0x3F] = UInt8(truncatingIfNeeded: windowId >> 24)
        record[0x8A] = focused ? 0x01 : 0x02
        let status = psn.withUnsafeBytes { psnBytes in
            record.withUnsafeBufferPointer { recordBytes in
                post(psnBytes.baseAddress, recordBytes.baseAddress)
            }
        }
        return status == 0
    }

    private static func opaquePointer(for event: CGEvent) -> UnsafeMutableRawPointer {
        Unmanaged.passUnretained(event).toOpaque()
    }

    private struct Symbols {
        var postEventToPid: SLEventPostToPidFunction?
        var setIntegerField: SLEventSetIntegerValueFieldFunction?
        var setWindowLocation: CGEventSetWindowLocationFunction?
        var postEventRecord: SLPSPostEventRecordToFunction?
        var getProcessForPID: GetProcessForPIDFunction?

        static func load() -> Symbols {
            let skyLight = dlopen(
                "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                RTLD_LAZY | RTLD_GLOBAL
            )
            let applicationServices = dlopen(
                "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
                RTLD_LAZY | RTLD_GLOBAL
            )
            return Symbols(
                postEventToPid: loadFunction(skyLight, "SLEventPostToPid"),
                setIntegerField: loadFunction(skyLight, "SLEventSetIntegerValueField"),
                setWindowLocation: loadFunction(skyLight, "CGEventSetWindowLocation"),
                postEventRecord: loadFunction(skyLight, "SLPSPostEventRecordTo")
                    ?? loadFunction(skyLight, "_SLPSPostEventRecordTo"),
                getProcessForPID: loadFunction(applicationServices, "GetProcessForPID")
                    ?? loadFunction(nil, "GetProcessForPID")
            )
        }

        private static func loadFunction<T>(
            _ handle: UnsafeMutableRawPointer?,
            _ name: String
        ) -> T? {
            guard let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: T.self)
        }
    }
}
