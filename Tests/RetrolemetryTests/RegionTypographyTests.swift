import XCTest
import AppKit
@testable import Retrolemetry

final class RegionTypographyTests: XCTestCase {
    func testAutomaticRegionAndManualOverrideWithoutLocation() {
        func place(_ lat: Double, _ lon: Double) -> GlobeCoordinate? { GlobeCoordinate(latitude: lat, longitude: lon) }
        XCTAssertEqual(WeatherRegionSelection.automatic.resolve(coordinate: place(32.0853,34.7818)), .israel)
        XCTAssertEqual(WeatherRegionSelection.automatic.resolve(coordinate: place(47.6062,-122.3321)), .northAmerica)
        XCTAssertEqual(WeatherRegionSelection.automatic.resolve(coordinate: place(19.4326,-99.1332)), .northAmerica)
        XCTAssertEqual(WeatherRegionSelection.automatic.resolve(coordinate: place(51.5074,-0.1278)), .europe)
        XCTAssertNil(WeatherRegionSelection.automatic.resolve(coordinate: nil))
        XCTAssertNil(WeatherRegionSelection.automatic.resolve(coordinate: place(35.6762,139.6503)))
        XCTAssertEqual(WeatherRegionSelection.europe.resolve(coordinate: nil), .europe)
        XCTAssertEqual(WeatherRegionSelection.northAmerica.resolve(coordinate: place(32.1,34.8)), .northAmerica)
        XCTAssertFalse(WeatherSnapshot().localForecastIsAvailable)
        XCTAssertTrue(WeatherSnapshot(updatedAt: Date()).localForecastIsAvailable)
        XCTAssertFalse(WeatherSnapshot(updatedAt: Date().addingTimeInterval(-7200)).localForecastIsAvailable)
    }

    func testAllMapsAndSamplesShareBoundedProjection() {
        for region in RadarRegion.allCases {
            XCTAssertEqual(region.sites.count, 6)
            XCTAssertGreaterThan(RadarMapGeometry.segments(for: region).count, 100)
            XCTAssertLessThan(RadarMapGeometry.segments(for: region).count, 1600)
            for edge in RadarMapGeometry.segments(for: region) {
                for value in [edge.x,edge.y,edge.z,edge.w] { XCTAssertTrue(value.isFinite); XCTAssertLessThan(abs(value), 1.1) }
            }
            var snapshot = WeatherSnapshot()
            snapshot.radarRegion = region
            snapshot.radarWeather = RadarWeatherPoint.preview(region: region)
            snapshot.radarUpdatedAt = Date()
            let targets = radarTargets(for: snapshot, mode: .temperature)
            XCTAssertEqual(targets.count, 6)
            for (site, target) in zip(region.sites, targets) {
                XCTAssertEqual(target.mapPosition, RadarMapGeometry.position(latitude: site.latitude, longitude: site.longitude, region: region))
            }
            let parts = URLComponents(url: RegionalWeatherFeed.url(for: region), resolvingAgainstBaseURL: false)!
            XCTAssertEqual(parts.queryItems?.first { $0.name == "latitude" }?.value, region.sites.map { String($0.latitude) }.joined(separator: ","))
        }
    }

    func testFiveIndependentGroupsKeepLegacyAppearanceAndBackups() throws {
        XCTAssertEqual(ConsoleFontRole.allCases.count, 5)
        let data = Data("{\"primary\":1.8,\"secondary\":1.35,\"other\":2}".utf8)
        var typography = try JSONDecoder().decode(ConsoleTypography.self, from: data)
        XCTAssertEqual(typography.scale(.dark, fallback: .other), 2)
        XCTAssertEqual(typography.scale(.secondary, fallback: .primary), 1.8)
        XCTAssertEqual(typography[.frameHeader], 2)
        XCTAssertEqual(typography[.frameFooter], 2)
        typography[.secondary] = 2.4
        XCTAssertEqual(typography.scale(.secondary, fallback: .primary), 2.4)
        XCTAssertEqual(typography.scale(.dark, fallback: .other), 2)
        typography[.dark] = 0.85
        typography[.frameHeader] = 3
        XCTAssertEqual(typography.primary, 1.8)
        XCTAssertEqual(typography[.frameFooter], 2)
        XCTAssertEqual(typography.scale(.dark, fallback: .other), 0.85)
        XCTAssertEqual(try JSONDecoder().decode(ConsoleTypography.self, from: JSONEncoder().encode(typography)), typography)
    }

    func testGlobalAndPerViewFontGroupsPersistWithoutRewritingOldValues() async {
        await MainActor.run {
            let suite = "RetrolemetryTests.\(UUID())", defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(1.8, forKey: "DockTelemetry.fontScale")
            defaults.set(1.35, forKey: "DockTelemetry.secondaryFontScale")
            defaults.set(2.0, forKey: "DockTelemetry.auxiliaryFontScale")
            let before = defaults.persistentDomain(forName: suite)! as NSDictionary
            let store = LayoutStore(defaults: defaults)
            XCTAssertEqual(before, defaults.persistentDomain(forName: suite)! as NSDictionary)
            let frame = store.frame(.radar,"radar")
            store.setFontScale(2.5,role:.dark,scene:.radar)
            store.setFontScale(3,role:.frameHeader,scene:.radar)
            XCTAssertEqual(store.typography(for:.signal)[.dark],2.5)
            XCTAssertEqual(store.typography(for:.signal)[.frameFooter],2)
            store.globalTypographyEnabled = false
            store.setFontScale(1.1,role:.frameFooter,scene:.radar)
            let reload = LayoutStore(defaults:defaults)
            XCTAssertEqual(reload.typography(for:.radar)[.frameFooter],1.1)
            XCTAssertEqual(reload.typography(for:.system)[.frameFooter],2)
            XCTAssertEqual(reload.frame(.radar,"radar"),frame)
            XCTAssertEqual(defaults.double(forKey:"DockTelemetry.fontScale"),1.8)
            XCTAssertEqual(defaults.double(forKey:"DockTelemetry.secondaryFontScale"),1.35)
        }
    }

    @MainActor
    func testDoubleClickDoesNotRunSingleClickAction() async throws {
        let view = HorizontalScrollView(frame: CGRect(x:0,y:0,width:960,height:540))
        var single = 0, double = 0
            view.onClick = { _ in single += 1 }
            view.onDoubleClick = { double += 1 }
            for count in [1,2] {
                let event = NSEvent.mouseEvent(with:.leftMouseDown,location:NSPoint(x:40,y:40),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:0,context:nil,eventNumber:count,clickCount:count,pressure:1)!
                view.mouseDown(with:event)
            }
        try await Task.sleep(for:.seconds(NSEvent.doubleClickInterval+0.1))
        XCTAssertEqual(single,0); XCTAssertEqual(double,1)
    }
}
