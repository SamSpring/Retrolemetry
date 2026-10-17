import XCTest
@testable import Retrolemetry

final class UpdaterTests: XCTestCase {
    private var info: [String: Any] {
        ["SUFeedURL": UpdateConfiguration.feedURL,
         "SUPublicEDKey": "rPCCnQ2uJbuBh7gnxN4ObX9SJGh+JLGDhiy8Qr9BeF8=",
         "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true,
         "SUSignedFeedFailureExpirationInterval": 0]
    }

    func testDedicatedHTTPSConfiguration() {
        XCTAssertTrue(UpdateConfiguration.isValid(info))
        XCTAssertEqual(UpdateConfiguration.bundleIdentifier, "io.github.SamSpring.Retrolemetry")
        XCTAssertEqual(UpdateConfiguration.feedURL, "https://samspring.github.io/Retrolemetry/appcast.xml")
    }

    func testMissingKeyOrWeakValidationCannotStart() {
        for field in ["SUPublicEDKey", "SUVerifyUpdateBeforeExtraction", "SURequireSignedFeed", "SUSignedFeedFailureExpirationInterval"] {
            var invalid = info
            invalid.removeValue(forKey: field)
            XCTAssertFalse(UpdateConfiguration.isValid(invalid))
        }
        var invalid = info
        invalid["SUPublicEDKey"] = "invalid"
        XCTAssertFalse(UpdateConfiguration.isValid(invalid))
    }

    func testUnrelatedOrInsecureFeedsCannotStart() {
        for feed in ["http://samspring.github.io/Retrolemetry/appcast.xml", "https://samspring.github.io/SpaceBar/appcast.xml"] {
            var invalid = info
            invalid["SUFeedURL"] = feed
            XCTAssertFalse(UpdateConfiguration.isValid(invalid))
        }
    }
}
