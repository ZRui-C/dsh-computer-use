import XCTest
import ApplicationServices
@testable import DSHComputerUseCore

final class AXActionAndRedactionTests: XCTestCase {
    // Creation and setting an AX messaging timeout do not query live UI or
    // require Accessibility access. Every attribute/action query is injected.
    private let element = AXUIElementCreateApplication(42)

    func testActionNamesUseDedicatedCopyActionNamesResult() {
        var copied = false
        let names = AXAccessibility.actionNames(element, copyActionNames: { _, output in
            copied = true
            output.pointee = ["AXPress", "AXShowMenu"] as CFArray
            return .success
        })

        XCTAssertTrue(copied)
        XCTAssertEqual(names, ["AXPress", "AXShowMenu"])
    }

    func testActionNamesFailClosedOnAXErrorOrInvalidResult() {
        let failed = AXAccessibility.actionNames(element, copyActionNames: { _, output in
            output.pointee = ["AXPress"] as CFArray
            return .cannotComplete
        })
        let empty = AXAccessibility.actionNames(element, copyActionNames: { _, _ in .success })
        let invalid = AXAccessibility.actionNames(element, copyActionNames: { _, output in
            output.pointee = [NSNumber(value: 123)] as CFArray
            return .success
        })

        XCTAssertEqual(failed, [])
        XCTAssertEqual(empty, [])
        XCTAssertEqual(invalid, [])
    }

    func testPressPerformsAdvertisedSemanticAction() {
        var performed: [String] = []
        let success = AXAccessibility.performPress(
            element,
            actionNames: { _ in ["AXShowMenu", "AXPress"] },
            performAction: { action, _ in performed.append(action); return true }
        )

        XCTAssertTrue(success)
        XCTAssertEqual(performed, ["AXPress"])
    }

    func testPressDoesNotInventUnsupportedAction() {
        let success = AXAccessibility.performPress(
            element,
            actionNames: { _ in ["AXShowMenu"] },
            performAction: { _, _ in XCTFail("Unsupported press must not run"); return true }
        )

        XCTAssertFalse(success)
    }

    func testPressPropagatesActionFailure() {
        XCTAssertFalse(AXAccessibility.performPress(
            element,
            actionNames: { _ in ["AXPress"] },
            performAction: { _, _ in false }
        ))
    }

    func testObservedNodeRetainsAvailableActionsAndPath() {
        let frame = Rect(x: 10, y: 20, width: 30, height: 40)
        let node = AXAccessibility.makeNode(
            element,
            pid: 42,
            depth: 12,
            path: [0, 2, 1],
            stringAttribute: { _, attribute in
                [AXAttribute.role: "AXButton", AXAttribute.title: "Submit", AXAttribute.description: "Send form"][attribute]
            },
            boolAttribute: { _, attribute in attribute == AXAttribute.enabled ? true : nil },
            frameAttribute: { _ in frame },
            actionNames: { _ in ["AXPress"] }
        )

        XCTAssertEqual(node.role, "AXButton")
        XCTAssertEqual(node.name, "Submit")
        XCTAssertEqual(node.description, "Send form")
        XCTAssertEqual(node.actions, ["AXPress"])
        XCTAssertEqual(node.enabled, true)
        XCTAssertEqual(node.frame, frame)
        XCTAssertEqual(node.target?.pid, 42)
        XCTAssertEqual(node.target?.path, [0, 2, 1])
        XCTAssertEqual(node.depth, 12)
        XCTAssertEqual(node.source, "ax")
        XCTAssertFalse(node.secure)
    }

    func testSecureNodeNeverQueriesOrSerializesSensitiveText() throws {
        for (role, subrole) in [
            (AXRole.secureTextField, ""),
            (AXRole.textField, AXRole.secureTextField),
            ("AXPasswordField", ""),
        ] {
            var queried: [String] = []
            let node = AXAccessibility.makeNode(
                element,
                pid: 42,
                depth: 20,
                path: [0, 1],
                stringAttribute: { _, attribute in
                    queried.append(attribute)
                    switch attribute {
                    case AXAttribute.role: return role
                    case AXAttribute.subrole: return subrole
                    default: return "must-never-be-read-or-serialized"
                    }
                },
                boolAttribute: { _, _ in nil },
                frameAttribute: { _ in nil },
                actionNames: { _ in [] }
            )

            XCTAssertEqual(queried, [AXAttribute.role, AXAttribute.subrole])
            XCTAssertTrue(node.secure)
            XCTAssertEqual(node.name, "[REDACTED]")
            XCTAssertEqual(node.value, "[REDACTED]")
            XCTAssertEqual(node.description, "[REDACTED]")
            XCTAssertEqual(node.target?.name, "[REDACTED]")
            let encoded = String(decoding: try JSONEncoder().encode(node), as: UTF8.self)
            XCTAssertFalse(encoded.contains("must-never-be-read-or-serialized"))
        }
    }
}
