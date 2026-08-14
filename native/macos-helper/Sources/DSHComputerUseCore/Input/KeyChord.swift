import Foundation
import CoreGraphics

/// A parsed keyboard chord: a set of modifier flags plus a virtual key code.
///
/// Stored with raw values so the struct is `Codable` and `Sendable`-friendly
/// while still exposing the CoreGraphics types through computed properties.
public struct KeyChord: Codable, Equatable {
    public var modifiersRaw: UInt64
    public var keyCodeRaw: UInt16
    public var key: String

    public var modifiers: CGEventFlags { CGEventFlags(rawValue: modifiersRaw) }
    public var keyCode: CGKeyCode { CGKeyCode(keyCodeRaw) }

    public init(modifiers: CGEventFlags, keyCode: CGKeyCode, key: String) {
        self.modifiersRaw = modifiers.rawValue
        self.keyCodeRaw = keyCode
        self.key = key
    }
}

/// Well-known macOS virtual key codes (mirrors of Carbon's `kVK_*` constants).
/// Declared here so the core stays free of the `Carbon` module dependency.
public enum VirtualKeyCodes {
    public static let a: CGKeyCode = 0x00
    public static let s: CGKeyCode = 0x01
    public static let d: CGKeyCode = 0x02
    public static let f: CGKeyCode = 0x03
    public static let h: CGKeyCode = 0x04
    public static let g: CGKeyCode = 0x05
    public static let z: CGKeyCode = 0x06
    public static let x: CGKeyCode = 0x07
    public static let c: CGKeyCode = 0x08
    public static let v: CGKeyCode = 0x09
    public static let b: CGKeyCode = 0x0B
    public static let q: CGKeyCode = 0x0C
    public static let w: CGKeyCode = 0x0D
    public static let e: CGKeyCode = 0x0E
    public static let r: CGKeyCode = 0x0F
    public static let y: CGKeyCode = 0x10
    public static let t: CGKeyCode = 0x11
    public static let key1: CGKeyCode = 0x12
    public static let key2: CGKeyCode = 0x13
    public static let key3: CGKeyCode = 0x14
    public static let key4: CGKeyCode = 0x15
    public static let key6: CGKeyCode = 0x16
    public static let key5: CGKeyCode = 0x17
    public static let equal: CGKeyCode = 0x18
    public static let key9: CGKeyCode = 0x19
    public static let key7: CGKeyCode = 0x1A
    public static let minus: CGKeyCode = 0x1B
    public static let key8: CGKeyCode = 0x1C
    public static let key0: CGKeyCode = 0x1D
    public static let rightBracket: CGKeyCode = 0x1E
    public static let o: CGKeyCode = 0x1F
    public static let u: CGKeyCode = 0x20
    public static let leftBracket: CGKeyCode = 0x21
    public static let i: CGKeyCode = 0x22
    public static let p: CGKeyCode = 0x23
    public static let `return`: CGKeyCode = 0x24
    public static let l: CGKeyCode = 0x25
    public static let j: CGKeyCode = 0x26
    public static let quote: CGKeyCode = 0x27
    public static let k: CGKeyCode = 0x28
    public static let semicolon: CGKeyCode = 0x29
    public static let backslash: CGKeyCode = 0x2A
    public static let comma: CGKeyCode = 0x2B
    public static let slash: CGKeyCode = 0x2C
    public static let n: CGKeyCode = 0x2D
    public static let m: CGKeyCode = 0x2E
    public static let period: CGKeyCode = 0x2F
    public static let tab: CGKeyCode = 0x30
    public static let space: CGKeyCode = 0x31
    public static let grave: CGKeyCode = 0x32
    public static let delete: CGKeyCode = 0x33
    public static let escape: CGKeyCode = 0x35
    public static let command: CGKeyCode = 0x37
    public static let shift: CGKeyCode = 0x38
    public static let capsLock: CGKeyCode = 0x39
    public static let option: CGKeyCode = 0x3A
    public static let control: CGKeyCode = 0x3B
    public static let rightShift: CGKeyCode = 0x3C
    public static let rightOption: CGKeyCode = 0x3D
    public static let rightControl: CGKeyCode = 0x3E
    public static let function: CGKeyCode = 0x3F
    public static let f17: CGKeyCode = 0x40
    public static let volumeUp: CGKeyCode = 0x48
    public static let volumeDown: CGKeyCode = 0x49
    public static let mute: CGKeyCode = 0x4A
    public static let f18: CGKeyCode = 0x4F
    public static let f19: CGKeyCode = 0x50
    public static let f20: CGKeyCode = 0x5A
    public static let f5: CGKeyCode = 0x60
    public static let f6: CGKeyCode = 0x61
    public static let f7: CGKeyCode = 0x62
    public static let f3: CGKeyCode = 0x63
    public static let f8: CGKeyCode = 0x64
    public static let f9: CGKeyCode = 0x65
    public static let f11: CGKeyCode = 0x67
    public static let f13: CGKeyCode = 0x69
    public static let f16: CGKeyCode = 0x6A
    public static let f14: CGKeyCode = 0x6B
    public static let f10: CGKeyCode = 0x6D
    public static let f12: CGKeyCode = 0x6F
    public static let f15: CGKeyCode = 0x71
    public static let help: CGKeyCode = 0x72
    public static let home: CGKeyCode = 0x73
    public static let pageUp: CGKeyCode = 0x74
    public static let forwardDelete: CGKeyCode = 0x75
    public static let f4: CGKeyCode = 0x76
    public static let end: CGKeyCode = 0x77
    public static let f2: CGKeyCode = 0x78
    public static let pageDown: CGKeyCode = 0x79
    public static let f1: CGKeyCode = 0x7A
    public static let leftArrow: CGKeyCode = 0x7B
    public static let rightArrow: CGKeyCode = 0x7C
    public static let downArrow: CGKeyCode = 0x7D
    public static let upArrow: CGKeyCode = 0x7E
}

/// Pure parser for keyboard chord strings such as `"cmd+shift+a"`.
public enum KeyChordParser {
    private static let modifierNames: [String: CGEventFlags] = [
        "cmd": .maskCommand,
        "command": .maskCommand,
        "shift": .maskShift,
        "alt": .maskAlternate,
        "option": .maskAlternate,
        "opt": .maskAlternate,
        "ctrl": .maskControl,
        "control": .maskControl,
        "fn": .maskSecondaryFn,
        "function": .maskSecondaryFn,
    ]

    private static let keyCodes: [String: CGKeyCode] = [
        "a": VirtualKeyCodes.a, "b": VirtualKeyCodes.b, "c": VirtualKeyCodes.c,
        "d": VirtualKeyCodes.d, "e": VirtualKeyCodes.e, "f": VirtualKeyCodes.f,
        "g": VirtualKeyCodes.g, "h": VirtualKeyCodes.h, "i": VirtualKeyCodes.i,
        "j": VirtualKeyCodes.j, "k": VirtualKeyCodes.k, "l": VirtualKeyCodes.l,
        "m": VirtualKeyCodes.m, "n": VirtualKeyCodes.n, "o": VirtualKeyCodes.o,
        "p": VirtualKeyCodes.p, "q": VirtualKeyCodes.q, "r": VirtualKeyCodes.r,
        "s": VirtualKeyCodes.s, "t": VirtualKeyCodes.t, "u": VirtualKeyCodes.u,
        "v": VirtualKeyCodes.v, "w": VirtualKeyCodes.w, "x": VirtualKeyCodes.x,
        "y": VirtualKeyCodes.y, "z": VirtualKeyCodes.z,
        "0": VirtualKeyCodes.key0, "1": VirtualKeyCodes.key1, "2": VirtualKeyCodes.key2,
        "3": VirtualKeyCodes.key3, "4": VirtualKeyCodes.key4, "5": VirtualKeyCodes.key5,
        "6": VirtualKeyCodes.key6, "7": VirtualKeyCodes.key7, "8": VirtualKeyCodes.key8,
        "9": VirtualKeyCodes.key9,
        "space": VirtualKeyCodes.space, " ": VirtualKeyCodes.space,
        "return": VirtualKeyCodes.return, "enter": VirtualKeyCodes.return,
        "tab": VirtualKeyCodes.tab,
        "escape": VirtualKeyCodes.escape, "esc": VirtualKeyCodes.escape,
        "delete": VirtualKeyCodes.delete, "backspace": VirtualKeyCodes.delete,
        "forwarddelete": VirtualKeyCodes.forwardDelete, "del": VirtualKeyCodes.forwardDelete,
        "up": VirtualKeyCodes.upArrow, "down": VirtualKeyCodes.downArrow,
        "left": VirtualKeyCodes.leftArrow, "right": VirtualKeyCodes.rightArrow,
        "home": VirtualKeyCodes.home, "end": VirtualKeyCodes.end,
        "pageup": VirtualKeyCodes.pageUp, "pagedown": VirtualKeyCodes.pageDown,
        "f1": VirtualKeyCodes.f1, "f2": VirtualKeyCodes.f2, "f3": VirtualKeyCodes.f3,
        "f4": VirtualKeyCodes.f4, "f5": VirtualKeyCodes.f5, "f6": VirtualKeyCodes.f6,
        "f7": VirtualKeyCodes.f7, "f8": VirtualKeyCodes.f8, "f9": VirtualKeyCodes.f9,
        "f10": VirtualKeyCodes.f10, "f11": VirtualKeyCodes.f11, "f12": VirtualKeyCodes.f12,
        "-": VirtualKeyCodes.minus, "=": VirtualKeyCodes.equal,
        "[": VirtualKeyCodes.leftBracket, "]": VirtualKeyCodes.rightBracket,
        "\\": VirtualKeyCodes.backslash, ";": VirtualKeyCodes.semicolon,
        "'": VirtualKeyCodes.quote, ",": VirtualKeyCodes.comma,
        ".": VirtualKeyCodes.period, "/": VirtualKeyCodes.slash,
        "`": VirtualKeyCodes.grave,
    ]

    /// Parses a `"modifier+modifier+key"` chord. Returns `nil` for empty input,
    /// multiple non-modifier keys, or an unknown key name.
    public static func parse(_ chord: String) -> KeyChord? {
        let trimmed = chord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard !parts.isEmpty else { return nil }

        var modifiers: CGEventFlags = []
        var keyName: String?

        for part in parts {
            if part.isEmpty { return nil }
            if let flag = modifierNames[part] {
                modifiers.insert(flag)
            } else {
                guard keyName == nil else { return nil }
                keyName = part
            }
        }

        guard let name = keyName, let code = keyCodes[name] else { return nil }
        return KeyChord(modifiers: modifiers, keyCode: code, key: name)
    }

    /// Looks up the virtual key code for a bare (unmodified) key name.
    public static func keyCode(for name: String) -> CGKeyCode? {
        keyCodes[name.trimmingCharacters(in: .whitespaces).lowercased()]
    }
}
