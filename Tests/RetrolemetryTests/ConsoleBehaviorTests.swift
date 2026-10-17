import XCTest
@testable import Retrolemetry

final class ConsoleBehaviorTests: XCTestCase {
    func testTypographyLoadsWithoutMigratingOrChangingSavedLayout() async {
        await MainActor.run {
            let suite = "RetrolemetryTests.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(1.8, forKey: "DockTelemetry.fontScale")
            defaults.set(1.35, forKey: "DockTelemetry.secondaryFontScale")
            defaults.set(2.0, forKey: "DockTelemetry.auxiliaryFontScale")
            let frame = ModuleFrame(x: 500, y: 63, width: 230, height: 255, visible: false)
            let saved = try! JSONEncoder().encode(["globe": frame])
            defaults.set(saved, forKey: "DockTelemetry.layout.v5.0")
            let initial = defaults.persistentDomain(forName: suite)! as NSDictionary
            let store = LayoutStore(defaults: defaults)
            XCTAssertTrue(store.globalTypographyEnabled)
            XCTAssertEqual(store.typography(for: .signal), ConsoleTypography(primary: 1.8, secondary: 1.35, other: 2))
            XCTAssertEqual(store.frame(.system, "globe"), frame)
            XCTAssertEqual(initial, defaults.persistentDomain(forName: suite)! as NSDictionary)
            store.globalTypographyEnabled = false
            store.setFontScale(0.9, role: .primary, scene: .signal)
            XCTAssertEqual(store.typography(for: .signal).primary, 0.9)
            XCTAssertEqual(store.typography(for: .system).primary, 1.8)
            XCTAssertEqual(defaults.data(forKey: "DockTelemetry.layout.v5.0"), saved)
            let reload = LayoutStore(defaults: defaults)
            XCTAssertEqual(reload.typography(for: .signal).primary, 0.9)
            store.globalTypographyEnabled = true
            store.setFontScale(2, role: .secondary, scene: .radar)
            XCTAssertEqual(store.typography(for: .system).secondary, 2)
            store.globalTypographyEnabled = false
            XCTAssertEqual(store.typography(for: .signal).primary, 0.9)
        }
    }

    func testTypographyReaches300PercentAndPersistsWithoutMovingModules() async {
        await MainActor.run {
            let suite = "RetrolemetryTests.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = LayoutStore(defaults: defaults)
            let frame = store.frame(.signal, "ioReadout")
            for role in ConsoleFontRole.allCases {
                store.setFontScale(3, role: role, scene: .signal)
                XCTAssertEqual(store.typography(for: .signal)[role], 3)
                store.setFontScale(5, role: role, scene: .signal)
                XCTAssertEqual(store.typography(for: .signal)[role], 3)
            }
            store.globalTypographyEnabled = false
            store.setFontScale(2.7, role: .secondary, scene: .radar)
            let reload = LayoutStore(defaults: defaults)
            XCTAssertEqual(reload.typography(for: .radar).secondary, 2.7)
            XCTAssertEqual(reload.typography(for: .signal).primary, 3)
            XCTAssertEqual(reload.frame(.signal, "ioReadout"), frame)
        }
    }

    func testHiddenModuleKeepsFrameAndCanBeRestored() async {
        await MainActor.run {
            let suite = "RetrolemetryTests.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = LayoutStore(defaults: defaults)
            let before = store.frame(.system, "globe")
            store.setVisible(false, scene: .system, module: "globe")
            let hidden = store.frame(.system, "globe")
            XCTAssertFalse(hidden.visible)
            XCTAssertEqual(hidden.x, before.x); XCTAssertEqual(hidden.width, before.width)
            store.setVisible(true, scene: .system, module: "globe")
            XCTAssertEqual(store.frame(.system, "globe"), before)
        }
    }

    func testTickerSelectionUsesResizedFrameAndTypography() {
        let frame = ModuleFrame(x: 130, y: 280, width: 420, height: 180)
        for scale in [0.65, 1, 2.0, 3.0] {
            let typography = ConsoleTypography(primary: scale, secondary: scale, other: scale)
            let top = frame.y + 7 + MarketTickerGeometry.headerHeight(typography) + 7
            let rowHeight = (frame.height - 14 - MarketTickerGeometry.headerHeight(typography) - 19) / 5
            for row in 0..<5 {
                let p = CGPoint(x: frame.x+20, y: top + Double(row)*(rowHeight+3) + rowHeight/2)
                XCTAssertEqual(MarketTickerGeometry.row(at: p, frame: frame, typography: typography), row)
            }
            XCTAssertNil(MarketTickerGeometry.row(at: CGPoint(x: frame.x, y: frame.y+3), frame: frame, typography: typography))
        }
    }

    func testStockFocusAndAutomaticRotationCanBeRestored() async {
        await MainActor.run {
            let model = MarketModel(preview: true)
            model.focus("RGTI"); XCTAssertEqual(model.focusedSymbol, "RGTI")
            model.focus("NOT-IN-PORTFOLIO"); XCTAssertEqual(model.focusedSymbol, "RGTI")
            model.focus("OKLO"); XCTAssertEqual(model.focusedSymbol, "OKLO")
            model.focus("OKLO"); XCTAssertNil(model.focusedSymbol)
        }
    }

    func testGlobeCoversBothHemispheresAndProjectionIsRound() {
        let longitudes = (0..<GlobeGeometry.meridianCount).map { GlobeGeometry.longitude($0, rotation: 0.2) }
        XCTAssertEqual(longitudes.filter { cos($0) > 0 }.count, 8)
        XCTAssertEqual(longitudes.filter { cos($0) < 0 }.count, 8)
        XCTAssertGreaterThan(GlobeCoastlines.degrees.count, 500)
        XCTAssertLessThan(GlobeCoastlines.degrees.count, 1200)
        for latitude in stride(from: -80.0, through: 80, by: 20) {
            let p = GlobeGeometry.project(latitude: latitude, longitude: 35, rotation: 2)
            XCTAssertEqual(p.x*p.x+p.y*p.y+p.z*p.z, 1, accuracy: 1e-10)
        }
        XCTAssertLessThan(GlobeGeometry.project(latitude: 45, longitude: 0, rotation: 0).y, 0)
        XCTAssertNil(GlobeCoordinate(latitude: .nan, longitude: 0))
    }

    func testTradingHoursRespectDSTWeekendsAndLunch() {
        func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
        XCTAssertFalse(TradingRegionActivity.newYork.isScheduledOpen(at: date("2026-03-06T14:29:00Z")))
        XCTAssertTrue(TradingRegionActivity.newYork.isScheduledOpen(at: date("2026-03-06T14:30:00Z")))
        XCTAssertTrue(TradingRegionActivity.newYork.isScheduledOpen(at: date("2026-03-09T13:30:00Z")))
        XCTAssertFalse(TradingRegionActivity.newYork.isScheduledOpen(at: date("2026-10-10T14:00:00Z")))
        XCTAssertTrue(TradingRegionActivity.tokyo.isScheduledOpen(at: date("2026-10-13T02:29:00Z")))
        XCTAssertFalse(TradingRegionActivity.tokyo.isScheduledOpen(at: date("2026-10-13T02:30:00Z")))
        XCTAssertTrue(TradingRegionActivity.tokyo.isScheduledOpen(at: date("2026-10-13T03:30:00Z")))
        XCTAssertFalse(TradingRegionActivity.tokyo.isScheduledOpen(at: date("2026-10-13T06:30:00Z")))
    }

    func testNativeTransitionStartsInPlaceAndFinishesOnTarget() {
        for style in SceneTransitionStyle.allCases {
            let incoming = ConsoleTransitionMotion(start: 100, duration: style.duration, style: style, direction: -1, incoming: true)
            XCTAssertEqual(incoming.uniforms(at: 100).x, 0)
            XCTAssertEqual(incoming.uniforms(at: 105).x, 1)
            XCTAssertEqual(incoming.uniforms(at: 100).w, -1)
        }
        XCTAssertEqual(ConsoleTransitionMotion.ease(0), 0)
        XCTAssertEqual(ConsoleTransitionMotion.ease(1), 1)
        let samples = (0...100).map { ConsoleTransitionMotion.ease(Double($0)/100) }
        XCTAssertEqual(samples, samples.sorted())
    }
}
