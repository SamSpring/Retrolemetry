import XCTest
import AppKit
import SwiftUI
@testable import Retrolemetry

final class DarkTypographyTests: XCTestCase {
    func testDimAppearanceOverridesEverySemanticRole() {
        let typography = ConsoleTypography(groups: ["primary": 2.8, "dark": 1.4, "secondary": 3,
                                                     "frameHeader": 2.2, "frameFooter": 2.5])
        for role in ConsoleFontRole.allCases {
            XCTAssertEqual(ConsoleTypography.resolvedRole(role, dimmed: true), .dark)
            XCTAssertEqual(typography.scale(role, dimmed: true), 1.4)
            XCTAssertEqual(typography.scale(role), typography[role])
        }
        XCTAssertEqual(ConsoleFontRole.secondary.title, "Main text")
        // Only the displayed name changes; existing saved/exported keys stay valid.
        XCTAssertEqual(ConsoleFontRole.secondary.rawValue, "secondary")
    }

    func testLegacyDimTextKeepsItsOriginalScaleUntilDarkIsAdjusted() {
        var typography = ConsoleTypography(primary: 1.8, secondary: 1.35, other: 2)
        XCTAssertEqual(typography.scale(.secondary, dimmed: true), 1.35)
        XCTAssertEqual(typography.scale(.secondary, fallback: .primary, dimmed: true), 1.8)
        XCTAssertEqual(typography.scale(.secondary, fallback: .other, dimmed: true), 2)
        typography[.secondary] = 3
        XCTAssertEqual(typography.scale(.secondary, dimmed: true), 1.35)
        typography[.dark] = 0.8
        XCTAssertEqual(typography.scale(.secondary, fallback: .other, dimmed: true), 0.8)
        XCTAssertEqual(typography.secondary, 3)
        XCTAssertEqual(typography.primary, 1.8)
    }

    func testTickerHeaderAndClickGeometryFollowDarkNotMain() {
        var typography = ConsoleTypography(groups: ["dark": 2, "secondary": 0.8])
        XCTAssertEqual(MarketTickerGeometry.headerHeight(typography), 22)
        typography[.secondary] = 3
        XCTAssertEqual(MarketTickerGeometry.headerHeight(typography), 22)
        typography[.dark] = 3
        XCTAssertEqual(MarketTickerGeometry.headerHeight(typography), 33)
    }

    @MainActor
    func testActualDimTextIgnoresMainSliderAndRespondsToDark() {
        func measured(main: Double, dark: Double, dimmed: Bool) -> NSSize {
            let root = Text("PORTFOLIO / LAST CHANGE")
                .consoleFont(12, role: .secondary)
                .consoleDimmed(dimmed)
                .fixedSize()
                .environment(\.consoleTypography, ConsoleTypography(groups: ["secondary": main, "dark": dark]))
            return NSHostingView(rootView: root).fittingSize
        }
        let dimSmall = measured(main: 0.8, dark: 1.4, dimmed: true)
        let dimLargeMain = measured(main: 3, dark: 1.4, dimmed: true)
        XCTAssertGreaterThan(dimSmall.width, 0)
        XCTAssertEqual(dimSmall.width, dimLargeMain.width, accuracy: 0.1)
        XCTAssertEqual(dimSmall.height, dimLargeMain.height, accuracy: 0.1)
        XCTAssertGreaterThan(measured(main: 0.8, dark: 3, dimmed: true).height, dimSmall.height)
        let bright = measured(main: 1.4, dark: 0.8, dimmed: false)
        XCTAssertEqual(bright.height, measured(main: 1.4, dark: 3, dimmed: false).height, accuracy: 0.1)
        XCTAssertGreaterThan(measured(main: 3, dark: 0.8, dimmed: false).height, bright.height)
    }

    @MainActor
    func testDimContainerOverridesNestedExplicitFontRoles() {
        func measured(dark: Double, primary: Double) -> NSSize {
            let root = HStack {
                Text("LAST").consoleFont(12, role: .secondary)
                Text("USD 123.45").consoleFont(12, role: .primary)
            }
            .consoleDimmed()
            .fixedSize()
            .environment(\.consoleTypography, ConsoleTypography(groups: ["primary": primary, "secondary": 3, "dark": dark]))
            return NSHostingView(rootView: root).fittingSize
        }
        let original = measured(dark: 1, primary: 1)
        XCTAssertEqual(original.width, measured(dark: 1, primary: 3).width, accuracy: 0.1)
        XCTAssertGreaterThan(measured(dark: 2, primary: 1).height, original.height)
    }
}
