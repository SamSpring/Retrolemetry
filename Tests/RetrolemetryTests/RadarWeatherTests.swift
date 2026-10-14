import XCTest
@testable import Retrolemetry

final class RadarWeatherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_200)

    private func fixture(rain: Any = 30.0, temperature: Any = 24.0, wind: Any = 12.0) throws -> Data {
        let hour = floor(now.timeIntervalSince1970 / 3600) * 3600
        let payloads: [[String: Any]] = RadarWeatherSite.all.map { site in
            ["latitude": site.latitude, "longitude": site.longitude,
             "current": ["time": now.timeIntervalSince1970, "temperature_2m": temperature,
                         "wind_speed_10m": wind, "wind_direction_10m": 270.0],
             "hourly": ["time": [hour-3600, hour, hour+3600], "precipitation_probability": [80.0, rain, 90.0]]]
        }
        return try JSONSerialization.data(withJSONObject: payloads)
    }

    func testBatchedForecastUsesCorrectLocationAndCurrentHour() throws {
        let result = try RegionalWeatherFeed.decode(fixture(), at: now)
        XCTAssertEqual(result.count, 6)
        XCTAssertEqual(result.map(\.site), RadarWeatherSite.all)
        XCTAssertEqual(result[2].site.name, "TEL AVIV")
        XCTAssertEqual(result[2].rainChance, 0.3)
        XCTAssertEqual(result[2].windDirection, 270)
        XCTAssertEqual(result[2].readout(for: .wind), "12 KM/H")
        XCTAssertEqual(result[2].readout(for: .precipitation), "30%")
    }

    func testMissingAndInvalidValuesAreNotInventedZeroes() throws {
        let missing = try RegionalWeatherFeed.decode(fixture(rain: NSNull(), temperature: NSNull(), wind: NSNull()), at: now)
        XCTAssertNil(missing[0].rainChance); XCTAssertNil(missing[0].windSpeed)
        XCTAssertEqual(missing[0].readout(for: .temperature), "N/A")
        let invalid = try RegionalWeatherFeed.decode(fixture(rain: 110.0, temperature: -200.0, wind: -1.0), at: now)
        XCTAssertNil(invalid[0].rainChance); XCTAssertNil(invalid[0].temperature); XCTAssertNil(invalid[0].windSpeed)
        let zero = try RegionalWeatherFeed.decode(fixture(rain: 0.0, wind: 0.0), at: now)
        XCTAssertEqual(zero[0].rainChance, 0); XCTAssertEqual(zero[0].windSpeed, 0)
    }

    func testStaleOrMismatchedBatchCannotMasqueradeAsLiveWeather() throws {
        XCTAssertThrowsError(try RegionalWeatherFeed.decode(fixture(), at: now.addingTimeInterval(7200)))
        var payloads = try JSONSerialization.jsonObject(with: fixture()) as! [[String: Any]]
        payloads[0]["latitude"] = 0.0
        XCTAssertThrowsError(try RegionalWeatherFeed.decode(JSONSerialization.data(withJSONObject: payloads), at: now))
        XCTAssertThrowsError(try RegionalWeatherFeed.decode(Data("[]".utf8), at: now))
        let offline = WeatherSnapshot()
        XCTAssertTrue(radarTargets(for: offline, mode: .precipitation).isEmpty)
        XCTAssertEqual(radarTargets(for: offline, mode: .decorative).count, 7)
    }

    func testMapProjectionAndTargetsUseSameGeography() {
        XCTAssertGreaterThan(RadarMapGeometry.segments.count, 100)
        XCTAssertLessThan(RadarMapGeometry.segments.count, 300)
        let north = RadarMapGeometry.position(latitude: 33.2, longitude: 35.5)
        let south = RadarMapGeometry.position(latitude: 29.6, longitude: 34.9)
        XCTAssertLessThan(north.y, south.y)
        for edge in RadarMapGeometry.segments {
            for value in [edge.x, edge.y, edge.z, edge.w] { XCTAssertTrue(value.isFinite); XCTAssertLessThan(abs(value), 1) }
        }
        var snapshot = WeatherSnapshot()
        snapshot.radarWeather = RadarWeatherPoint.preview()
        snapshot.radarUpdatedAt = Date()
        let targets = radarTargets(for: snapshot, mode: .wind)
        XCTAssertEqual(targets.count, 6)
        let site = RadarWeatherSite.all[2]
        XCTAssertEqual(targets[2].mapPosition, RadarMapGeometry.position(latitude: site.latitude, longitude: site.longitude))
        XCTAssertEqual(targets[2].heading, (snapshot.radarWeather[2].windDirection ?? 0) + 90)
    }

    func testBatchRequestDoesNotSendPersonalLocationOrCredentials() {
        let params = URLComponents(url: RegionalWeatherFeed.url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(params.first { $0.name == "latitude" }?.value?.split(separator: ",").count, 6)
        XCTAssertFalse(params.contains { ["apikey", "token"].contains($0.name) })
        XCTAssertEqual(params.first { $0.name == "wind_speed_unit" }?.value, "kmh")
    }
}
