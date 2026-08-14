import XCTest
@testable import DSHComputerUseCore

final class DSHProfileManifestInspectorTests: XCTestCase {
    func testMissingDependencyIsMissing() {
        XCTAssertEqual(status([:]), .missing)
        XCTAssertEqual(status([
            "dsh": ["profile": ["bundles": ["dsh-computer-use"]]],
        ]), .missing)
    }

    func testDependencyWithoutBundleNeedsRepair() {
        XCTAssertEqual(status([
            "dependencies": ["dsh-computer-use": "link:/tmp/plugin"],
            "dsh": ["profile": ["bundles": ["@deepseek-ai/dsh-base"]]],
        ]), .dependencyOnly)
    }

    func testDependencyAndBundleAreActive() {
        XCTAssertEqual(status([
            "dependencies": ["dsh-computer-use": "file:/Applications/Plugin"],
            "dsh": [
                "profile": [
                    "bundles": ["@deepseek-ai/dsh-base", "dsh-computer-use"],
                ],
            ],
        ]), .active)
    }

    func testMalformedManifestIsMissing() {
        XCTAssertEqual(
            DSHProfileManifestInspector.pluginStatus(
                in: Data("not-json".utf8),
                packageName: "dsh-computer-use"
            ),
            .missing
        )
    }

    private func status(_ object: [String: Any]) -> DSHProfilePluginStatus {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return DSHProfileManifestInspector.pluginStatus(
            in: data,
            packageName: "dsh-computer-use"
        )
    }
}
