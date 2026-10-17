import Foundation
import simd

/// Public, fixed forecast samples. These are not the user's location or radar echoes.
struct RadarWeatherSite: Equatable {
    let name: String
    let latitude: Double
    let longitude: Double

    static let all: [Self] = [
        Self(name: "NORTH", latitude: 33.2075, longitude: 35.5707),
        Self(name: "HAIFA", latitude: 32.7940, longitude: 34.9896),
        Self(name: "TEL AVIV", latitude: 32.0853, longitude: 34.7818),
        Self(name: "JERUSALEM", latitude: 31.7683, longitude: 35.2137),
        Self(name: "BEER SHEVA", latitude: 31.2520, longitude: 34.7915),
        Self(name: "EILAT", latitude: 29.5581, longitude: 34.9482)
    ]
}

struct RadarWeatherPoint {
    let site: RadarWeatherSite
    let temperature: Double?
    let windSpeed: Double?
    let windDirection: Double?
    let rainChance: Double?
    let forecastAt: Date

    func value(for mode: RadarTargetMode) -> Double? {
        switch mode {
        case .precipitation: rainChance
        case .temperature: temperature
        case .wind: windSpeed
        case .decorative: nil
        }
    }

    func readout(for mode: RadarTargetMode) -> String {
        guard let value = value(for: mode) else { return "N/A" }
        switch mode {
        case .precipitation: return String(format: "%.0f%%", value * 100)
        case .temperature: return String(format: "%.0f°C", value)
        case .wind: return String(format: "%.0f KM/H", value)
        case .decorative: return "DEMO"
        }
    }

    static func preview(at date: Date = Date(), region: RadarRegion = .israel) -> [Self] {
        region.sites.enumerated().map { i, site in
            Self(site: site, temperature: 20 + Double(i)*1.5,
                 windSpeed: 9 + Double(i)*3, windDirection: Double(210 + i*12),
                 rainChance: [0.6, 0.35, 0.2, 0.4, 0.1, 0.02][i], forecastAt: date)
        }
    }
}

enum RegionalWeatherFeed {
    static var url: URL { url(for: .israel) }
    static func url(for region: RadarRegion) -> URL {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            URLQueryItem(name: "latitude", value: region.sites.map { String($0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: region.sites.map { String($0.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "current", value: "temperature_2m,wind_speed_10m,wind_direction_10m"),
            URLQueryItem(name: "hourly", value: "precipitation_probability"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "GMT")
        ]
        return parts.url!
    }

    static func decode(_ data: Data, region: RadarRegion = .israel, at now: Date = Date()) throws -> [RadarWeatherPoint] {
        let payloads = try JSONDecoder().decode([Payload].self, from: data)
        guard payloads.count == region.sites.count else { throw URLError(.cannotParseResponse) }
        return try zip(region.sites, payloads).map { site, payload in
            // The batch is returned in request order. Reject a mismatched location rather
            // than pinning another area's forecast to this target.
            guard abs(site.latitude - payload.latitude) < 0.3,
                  abs(site.longitude - payload.longitude) < 0.3 else { throw URLError(.cannotParseResponse) }
            func valid(_ value: Double?, _ range: ClosedRange<Double>) -> Double? {
                value.flatMap { $0.isFinite && range.contains($0) ? $0 : nil }
            }
            let count = min(payload.hourly.time.count, payload.hourly.precipitationProbability.count)
            let hour = (0..<count).first { index in
                let timestamp = payload.hourly.time[index]
                return timestamp <= now.timeIntervalSince1970 && timestamp + 3600 > now.timeIntervalSince1970
            }
            let rain = hour.flatMap { valid(payload.hourly.precipitationProbability[$0], 0...100) }.map { $0 / 100 }
            let timestamp = payload.current.time
            guard timestamp.isFinite, abs(timestamp - now.timeIntervalSince1970) < 3600 else {
                throw URLError(.cannotParseResponse)
            }
            return RadarWeatherPoint(site: site,
                temperature: valid(payload.current.temperature, -90...65),
                windSpeed: valid(payload.current.windSpeed, 0...500),
                windDirection: valid(payload.current.windDirection, 0...360), rainChance: rain,
                forecastAt: Date(timeIntervalSince1970: timestamp))
        }
    }

    private struct Payload: Decodable {
        let latitude: Double
        let longitude: Double
        let current: Current
        let hourly: Hourly
        struct Current: Decodable {
            let time: Double
            let temperature: Double?
            let windSpeed: Double?
            let windDirection: Double?
            enum CodingKeys: String, CodingKey {
                case time, temperature = "temperature_2m", windSpeed = "wind_speed_10m", windDirection = "wind_direction_10m"
            }
        }
        struct Hourly: Decodable {
            let time: [Double]
            let precipitationProbability: [Double?]
            enum CodingKeys: String, CodingKey { case time, precipitationProbability = "precipitation_probability" }
        }
    }
}

/// Same inexpensive local projection for the Metal layer and static layout preview.
enum RadarMapGeometry {
    static func position(latitude: Double, longitude: Double, region: RadarRegion = .israel) -> SIMD2<Float> {
        let center: (lon: Double, lat: Double, span: Double)
        switch region {
        case .israel: center = (35.05, 31.45, 2.25)
        case .northAmerica: center = (-110, 45, 58)
        case .europe: center = (10, 53, 30)
        }
        let scaleLatitude = region == .israel ? 32 : center.lat
        return SIMD2(Float((longitude - center.lon) * cos(scaleLatitude * .pi / 180) / center.span), Float((center.lat - latitude) / center.span))
    }
    static var segments: [SIMD4<Float>] { segments(for: .israel) }
    static func segments(for region: RadarRegion) -> [SIMD4<Float>] { cached[region] ?? [] }
    private static let cached: [RadarRegion: [SIMD4<Float>]] = {
        func edges(_ ring: [SIMD2<Float>]) -> [SIMD4<Float>] {
            zip(ring, ring.dropFirst()).map { a, b in
                let p = position(latitude: Double(a.y), longitude: Double(a.x))
                let q = position(latitude: Double(b.y), longitude: Double(b.x))
                return SIMD4(p.x, p.y, q.x, q.y)
            }
        }
        func projected(_ edges: [SIMD4<Float>], region: RadarRegion) -> [SIMD4<Float>] {
            edges.map { edge in
                let p = position(latitude: Double(edge.y), longitude: Double(edge.x), region: region)
                let q = position(latitude: Double(edge.w), longitude: Double(edge.z), region: region)
                return SIMD4(p.x, p.y, q.x, q.y)
            }
        }
        return [.israel: edges(RadarMapData.israel) + edges(RadarMapData.telAviv),
                .northAmerica: projected(RegionalMapData.northAmerica, region: .northAmerica),
                .europe: projected(RegionalMapData.europe, region: .europe)]
    }()
    static var countrySegmentCount: Int { RadarMapData.israel.count - 1 }
    static func countrySegmentCount(for region: RadarRegion) -> Int {
        region == .israel ? countrySegmentCount : segments(for: region).count
    }
}
