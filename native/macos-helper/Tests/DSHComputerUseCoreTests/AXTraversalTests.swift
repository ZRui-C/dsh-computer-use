import XCTest
@testable import DSHComputerUseCore

/// Synthetic trees exercise the actual traversal without an Aqua session or
/// Accessibility permission. The child reader honors the same bounded-prefix
/// contract as AXUIElementCopyAttributeValues.
final class AXTraversalTests: XCTestCase {
    private func observe(
        _ tree: [Int: [Int]],
        maxDepth: Int = AXAccessibility.defaultMaxDepth,
        maxNodes: Int = 200
    ) -> AXObservationResult {
        AXTreeTraversal.observe(
            root: 0,
            maxDepth: maxDepth,
            maxNodes: maxNodes,
            children: { element, limit in Array((tree[element] ?? []).prefix(limit)) },
            makeNode: { element, depth, path in
                AXNode(
                    role: "AXGroup",
                    name: String(element),
                    target: TargetDescriptor(pid: 42, path: path),
                    depth: depth
                )
            }
        )
    }

    func testFindsChromeLikeContentBeyondEightContainerLevels() {
        let tree = Dictionary(uniqueKeysWithValues: (0..<40).map { ($0, [$0 + 1]) })
        let result = observe(tree)

        XCTAssertEqual(result.nodes.count, 41)
        XCTAssertEqual(result.nodes.last?.name, "40")
        XCTAssertEqual(result.nodes.last?.depth, 40)
        XCTAssertEqual(result.nodes.last?.target?.path, Array(repeating: 0, count: 40))
        XCTAssertFalse(result.truncated)
    }

    func testPreservesDepthFirstOrderAndResolvableChildIndexes() {
        let result = observe([0: [1, 2], 1: [3, 4], 3: [5]])

        XCTAssertEqual(result.nodes.compactMap(\.name), ["0", "1", "3", "5", "4", "2"])
        XCTAssertEqual(result.nodes.map(\.depth), [0, 1, 2, 3, 2, 1])
        XCTAssertEqual(result.nodes.compactMap { $0.target?.path }, [[], [0], [0, 0], [0, 0, 0], [0, 1], [1]])
        XCTAssertTrue(result.nodes.allSatisfy { $0.target?.pid == 42 && $0.source == "ax" })
        XCTAssertFalse(result.truncated)
    }

    func testReportsDepthCutoffOnlyWhenDescendantsAreOmitted() {
        let result = observe([0: [1], 1: [2]], maxDepth: 1)

        XCTAssertEqual(result.nodes.compactMap(\.name), ["0", "1"])
        XCTAssertTrue(result.hitDepthLimit)
        XCTAssertFalse(result.hitNodeLimit)
        XCTAssertFalse(observe([0: [1]], maxDepth: 1).truncated)
    }

    func testDepthCutoffContinuesWithRemainingSiblings() {
        let result = observe([0: [1, 2], 1: [3]], maxDepth: 1)

        XCTAssertEqual(result.nodes.compactMap(\.name), ["0", "1", "2"])
        XCTAssertTrue(result.hitDepthLimit)
        XCTAssertFalse(result.hitNodeLimit)
    }

    func testReportsNodeCutoffForUnvisitedSibling() {
        let result = observe([0: [1, 2]], maxNodes: 2)

        XCTAssertEqual(result.nodes.compactMap(\.name), ["0", "1"])
        XCTAssertTrue(result.hitNodeLimit)
        XCTAssertFalse(result.hitDepthLimit)
    }

    func testReportsNodeCutoffForUnvisitedDescendant() {
        let result = observe([0: [1], 1: [2]], maxNodes: 2)

        XCTAssertEqual(result.nodes.count, 2)
        XCTAssertTrue(result.hitNodeLimit)
        XCTAssertFalse(result.hitDepthLimit)
    }

    func testExactNodeBudgetIsNotReportedAsTruncated() {
        XCTAssertFalse(observe([0: [1, 2]], maxNodes: 3).truncated)
        XCTAssertFalse(observe([0: [1], 1: [2]], maxDepth: 2, maxNodes: 3).truncated)
        XCTAssertFalse(observe([:], maxDepth: 0, maxNodes: 1).truncated)
    }

    func testDescendantsKeepPriorityWhenPendingSiblingQueueFillsBudget() {
        let result = observe([0: [1, 2, 3, 4], 1: [5, 6], 5: [7]], maxNodes: 4)

        XCTAssertEqual(result.nodes.compactMap(\.name), ["0", "1", "5", "7"])
        XCTAssertEqual(result.nodes.last?.target?.path, [0, 0, 0])
        XCTAssertTrue(result.hitNodeLimit)
    }

    func testCanReportBothCutoffs() {
        let result = observe([0: [1, 2, 3], 1: [4]], maxDepth: 1, maxNodes: 2)

        XCTAssertEqual(result.nodes.count, 2)
        XCTAssertTrue(result.hitDepthLimit)
        XCTAssertTrue(result.hitNodeLimit)
    }

    func testZeroAndNegativeBudgetsDoNotQueryTree() {
        for budget in [0, -1, Int.min] {
            let result = AXTreeTraversal.observe(
                root: 0,
                maxDepth: 64,
                maxNodes: budget,
                children: { _, _ in XCTFail("Must not query children"); return [] },
                makeNode: { _, _, _ in XCTFail("Must not read nodes"); return AXNode(role: "unused") }
            )
            XCTAssertTrue(result.nodes.isEmpty)
            XCTAssertTrue(result.hitNodeLimit)
        }
    }

    func testNegativeDepthKeepsOnlyRootAndReportsDescendants() {
        let result = observe([0: [1]], maxDepth: -1)

        XCTAssertEqual(result.nodes.count, 1)
        XCTAssertTrue(result.hitDepthLimit)
        XCTAssertFalse(result.hitNodeLimit)
    }

    func testVeryWideTreeUsesBoundedChildReadsAndHardNodeCeiling() {
        var requestedLimits: [Int] = []
        let result = AXTreeTraversal.observe(
            root: 0,
            maxDepth: 64,
            maxNodes: Int.max,
            children: { element, limit in
                requestedLimits.append(limit)
                return element == 0 ? Array((1...1_000_000).prefix(limit)) : []
            },
            makeNode: { _, depth, path in
                AXNode(role: "AXGroup", target: TargetDescriptor(path: path), depth: depth)
            }
        )

        XCTAssertEqual(result.nodes.count, AXAccessibility.maximumNodes)
        XCTAssertEqual(requestedLimits.count, AXAccessibility.maximumNodes)
        XCTAssertEqual(requestedLimits.max(), AXAccessibility.maximumNodes)
        XCTAssertEqual(result.nodes.last?.target?.path, [AXAccessibility.maximumNodes - 2])
        XCTAssertTrue(result.hitNodeLimit)
    }

    func testCyclesAreBoundedByDepthAndNodes() {
        let depthLimited = observe([0: [0]], maxDepth: Int.max, maxNodes: Int.max)
        XCTAssertEqual(depthLimited.nodes.count, AXAccessibility.maximumDepth + 1)
        XCTAssertTrue(depthLimited.hitDepthLimit)
        XCTAssertFalse(depthLimited.hitNodeLimit)

        let nodeLimited = observe([0: [0]], maxNodes: 5)
        XCTAssertEqual(nodeLimited.nodes.count, 5)
        XCTAssertTrue(nodeLimited.hitNodeLimit)
        XCTAssertFalse(nodeLimited.hitDepthLimit)
    }
}
