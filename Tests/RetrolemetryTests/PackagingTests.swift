import XCTest
@testable import Retrolemetry

final class PackagingTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testOnlyLocationResourceCapabilityIsDeclared() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Retrolemetry.entitlements"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Bool])
        XCTAssertEqual(plist, ["com.apple.security.personal-information.location": true])
    }

    func testBothSigningModesIncludeLocationEntitlements() throws {
        let script = try String(contentsOf: root.appendingPathComponent("scripts/package_app.sh"), encoding: .utf8)
        let signingCommands = script.split(separator: "\n").filter { $0.contains("codesign --force") }
        XCTAssertEqual(signingCommands.count, 2)
        for command in signingCommands {
            XCTAssertTrue(command.contains("--entitlements Resources/Retrolemetry.entitlements"))
        }
        XCTAssertTrue(script.contains("Print :com.apple.security.personal-information.location"))
    }
}
