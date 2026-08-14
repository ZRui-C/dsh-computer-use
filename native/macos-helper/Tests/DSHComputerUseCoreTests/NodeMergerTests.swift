import XCTest
import CoreGraphics
import DSHComputerUseCore

final class NodeMergerTests: XCTestCase {
    func testOCRNodesAreConvertedToGlobalPoints() {
        let observations = [
            OCRTextObservation(text: "Hello", confidence: 0.9, frame: Rect(x: 200, y: 100, width: 100, height: 40))
        ]
        let nodes = NodeMerger.ocrNodes(
            from: observations,
            origin: CGPoint(x: 0, y: 0),
            scale: 2,
            existingAXNodes: []
        )

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].source, "ocr")
        XCTAssertEqual(nodes[0].role, "AXStaticText")
        XCTAssertEqual(nodes[0].name, "Hello")
        XCTAssertEqual(nodes[0].frame, Rect(x: 100, y: 50, width: 50, height: 20))
    }

    func testOCRNodesDedupAgainstAXText() {
        let existing = [
            AXNode(role: "AXStaticText", name: "Hello", value: "Hello", depth: 1, source: "ax"),
        ]
        let observations = [
            OCRTextObservation(text: "Hello", confidence: 0.9, frame: Rect(x: 0, y: 0, width: 10, height: 10)),
            OCRTextObservation(text: "World", confidence: 0.8, frame: Rect(x: 0, y: 10, width: 10, height: 10)),
        ]
        let nodes = NodeMerger.ocrNodes(
            from: observations,
            origin: CGPoint(x: 0, y: 0),
            scale: 1,
            existingAXNodes: existing
        )

        // "Hello" is dropped (already represented by AX); "World" is kept.
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].name, "World")
    }

    func testOCRNodesSkipEmptyText() {
        let observations = [
            OCRTextObservation(text: "   ", confidence: 0.9, frame: Rect(x: 0, y: 0, width: 10, height: 10)),
        ]
        let nodes = NodeMerger.ocrNodes(
            from: observations,
            origin: CGPoint(x: 0, y: 0),
            scale: 1,
            existingAXNodes: []
        )
        XCTAssertTrue(nodes.isEmpty)
    }

    func testAXNodeTextMatches() {
        let node = AXNode(role: "AXStaticText", name: "Hello World", value: nil)
        XCTAssertTrue(node.textMatches("  hello world  "))
        XCTAssertTrue(node.textMatches("Hello World"))
        XCTAssertFalse(node.textMatches("Goodbye"))
        XCTAssertFalse(node.textMatches(""))
    }
}
