import Foundation
import XCTest
@testable import DSHComputerUseCore

final class DSHInstallationTargetTests: XCTestCase {
    func testProfilesHaveIndependentManifestsAndPreferences() {
        let home = URL(fileURLWithPath: "/tmp/Custom DSH Home")
        XCTAssertEqual(DSHInstallationTarget.web.manifestURL(dshHome: home).path,
                       "/tmp/Custom DSH Home/profiles/web/package.json")
        XCTAssertEqual(DSHInstallationTarget.desktop.manifestURL(dshHome: home).path,
                       "/tmp/Custom DSH Home/profiles/desktop/package.json")
        XCTAssertEqual(DSHInstallationTarget.web.executablePreferenceKey, "dshExecutable")
        XCTAssertNotEqual(DSHInstallationTarget.web.executablePreferenceKey,
                          DSHInstallationTarget.desktop.executablePreferenceKey)
    }

    func testInstallUsesSelectedProfileAndOneLiteralPackageArgument() {
        let plugin = URL(fileURLWithPath: "/tmp/DSH's $HOME; example.app/Contents/Resources/Plugin")
        for target in DSHInstallationTarget.allCases {
            XCTAssertEqual(target.installArguments(pluginDirectory: plugin), [
                "plugin", "--profile", target.rawValue, "add", "--save-exact", "file:\(plugin.path)",
            ])
        }
    }

    func testDesktopSelectionAcceptsAppAndItsBundledCommandOnly() {
        let app = URL(fileURLWithPath: "/tmp/Moved Apps/DeepSeek Harness.app")
        let launcher = DSHInstallationTarget.desktopLauncher(in: app)
        XCTAssertEqual(launcher.path, "/tmp/Moved Apps/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh")
        XCTAssertEqual(DSHInstallationTarget.desktopApplication(for: app), app)
        XCTAssertEqual(DSHInstallationTarget.desktopApplication(for: launcher), app)
        for path in ["/usr/local/bin/dsh", "/tmp/node_modules/.bin/dsh", "/tmp/runtime/cli/bin/dsh",
                     "/tmp/not-an-app/Contents/Resources/runtime/cli/bin/dsh"] {
            XCTAssertNil(DSHInstallationTarget.desktopApplication(for: URL(fileURLWithPath: path)))
        }
    }

    func testDesktopCommandSymlinksResolveWithoutExecutingThem() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Moved Harness.app")
        let launcher = DSHInstallationTarget.desktopLauncher(in: app)
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 99\n".utf8).write(to: launcher)
        let link = directory.appendingPathComponent("dsh")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: launcher)
        XCTAssertEqual(DSHInstallationTarget.desktopApplication(for: link)?.path, app.resolvingSymlinksInPath().path)
    }
}
