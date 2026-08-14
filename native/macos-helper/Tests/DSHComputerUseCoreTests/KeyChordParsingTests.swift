import XCTest
import CoreGraphics
import DSHComputerUseCore

final class KeyChordParsingTests: XCTestCase {
    func testBareKey() throws {
        let chord = try XCTUnwrap(KeyChordParser.parse("a"))
        XCTAssertEqual(chord.key, "a")
        XCTAssertEqual(chord.keyCodeRaw, VirtualKeyCodes.a)
        XCTAssertTrue(chord.modifiers.isEmpty)
    }

    func testCommandShiftChord() throws {
        let chord = try XCTUnwrap(KeyChordParser.parse("cmd+shift+a"))
        XCTAssertEqual(chord.key, "a")
        XCTAssertEqual(chord.keyCodeRaw, VirtualKeyCodes.a)
        XCTAssertTrue(chord.modifiers.contains(.maskCommand))
        XCTAssertTrue(chord.modifiers.contains(.maskShift))
        XCTAssertFalse(chord.modifiers.contains(.maskAlternate))
    }

    func testControlAltDeleteChord() throws {
        let chord = try XCTUnwrap(KeyChordParser.parse("ctrl+alt+delete"))
        XCTAssertEqual(chord.key, "delete")
        XCTAssertEqual(chord.keyCodeRaw, VirtualKeyCodes.delete)
        XCTAssertTrue(chord.modifiers.contains(.maskControl))
        XCTAssertTrue(chord.modifiers.contains(.maskAlternate))
    }

    func testAliasesAndArrows() throws {
        XCTAssertEqual(KeyChordParser.parse("command+option+z")?.key, "z")
        XCTAssertEqual(KeyChordParser.parse("command+option+z")?.keyCodeRaw, VirtualKeyCodes.z)

        let arrow = try XCTUnwrap(KeyChordParser.parse("up"))
        XCTAssertEqual(arrow.keyCodeRaw, VirtualKeyCodes.upArrow)

        let functionKey = try XCTUnwrap(KeyChordParser.parse("f5"))
        XCTAssertEqual(functionKey.keyCodeRaw, VirtualKeyCodes.f5)

        let space = try XCTUnwrap(KeyChordParser.parse("space"))
        XCTAssertEqual(space.keyCodeRaw, VirtualKeyCodes.space)
    }

    func testCaseAndWhitespaceInsensitive() throws {
        let chord = try XCTUnwrap(KeyChordParser.parse("  Cmd + Shift + A  "))
        XCTAssertEqual(chord.key, "a")
        XCTAssertTrue(chord.modifiers.contains(.maskCommand))
        XCTAssertTrue(chord.modifiers.contains(.maskShift))
    }

    func testInvalidChordsReturnNil() {
        XCTAssertNil(KeyChordParser.parse(""))
        XCTAssertNil(KeyChordParser.parse("+"))
        XCTAssertNil(KeyChordParser.parse("cmd+"))
        XCTAssertNil(KeyChordParser.parse("a+b"))
        XCTAssertNil(KeyChordParser.parse("cmd+notakey"))
    }

    func testKeyCodeLookup() {
        XCTAssertEqual(KeyChordParser.keyCode(for: "a"), VirtualKeyCodes.a)
        XCTAssertEqual(KeyChordParser.keyCode(for: "return"), VirtualKeyCodes.return)
        XCTAssertEqual(KeyChordParser.keyCode(for: "0"), VirtualKeyCodes.key0)
        XCTAssertNil(KeyChordParser.keyCode(for: "nope"))
    }

    func testKeyChordCodableRoundTrip() throws {
        let chord = KeyChord(modifiers: [.maskCommand, .maskShift], keyCode: VirtualKeyCodes.a, key: "a")
        let data = try JSONEncoder().encode(chord)
        let decoded = try JSONDecoder().decode(KeyChord.self, from: data)
        XCTAssertEqual(decoded, chord)
    }
}
