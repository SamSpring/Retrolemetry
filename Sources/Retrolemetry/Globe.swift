import Foundation

struct GlobeCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
    init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude; self.longitude = longitude
    }
}

enum GlobeGeometry {
    static func project(latitude: Double, longitude: Double, rotation: Double) -> SIMD3<Double> {
        let lat = latitude * .pi / 180, lon = longitude * .pi / 180 + rotation
        return SIMD3(cos(lat) * sin(lon), -sin(lat), cos(lat) * cos(lon))
    }
    /// 16 complete pole-to-pole meridians, spread around all 360 degrees.
    static let meridianCount = 16
    static func longitude(_ index: Int, rotation: Double) -> Double { Double(index) * 2 * .pi / Double(meridianCount) + rotation }
    static func region(longitude: Double, latitude: Double) -> Int {
        if (-130 ... -60).contains(longitude), (24...51).contains(latitude) { return 1 }
        if (-20...45).contains(longitude), (34...72).contains(latitude) { return 2 }
        if (60...155).contains(longitude), (-10...58).contains(latitude) { return 3 }
        return 0
    }
    /// Two float4 endpoints per edge; the first endpoint carries its region tag.
    static let coastlines: [SIMD4<Float>] = GlobeCoastlines.degrees.flatMap { edge in
        let region = region(longitude: Double(edge.x + edge.z) / 2, latitude: Double(edge.y + edge.w) / 2)
        return [SIMD4(edge.x * .pi / 180, edge.y * .pi / 180, Float(region), 0), SIMD4(edge.z * .pi / 180, edge.w * .pi / 180, 0, 0)]
    }
}

struct TradingSession {
    let zone: String
    let ranges: [Range<Int>]
    func isScheduledOpen(at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, (2...6).contains(weekday) else { return false }
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return ranges.contains { $0.contains(minute) }
    }
}

/// Regular weekday sessions only: DST and lunch breaks, but no holiday/early-close feed.
struct TradingRegionActivity {
    var us: Bool
    var europe: Bool
    var asia: Bool
    static let newYork = TradingSession(zone: "America/New_York", ranges: [570..<960])
    static let london = TradingSession(zone: "Europe/London", ranges: [480..<990])
    static let frankfurt = TradingSession(zone: "Europe/Berlin", ranges: [540..<1050])
    static let tokyo = TradingSession(zone: "Asia/Tokyo", ranges: [540..<690, 750..<930])
    static let hongKong = TradingSession(zone: "Asia/Hong_Kong", ranges: [570..<720, 780..<960])
    init(at date: Date) {
        us = Self.newYork.isScheduledOpen(at: date)
        europe = Self.london.isScheduledOpen(at: date) || Self.frankfurt.isScheduledOpen(at: date)
        asia = Self.tokyo.isScheduledOpen(at: date) || Self.hongKong.isScheduledOpen(at: date)
    }
    subscript(_ region: Int) -> Bool {
        switch region { case 1: us; case 2: europe; case 3: asia; default: false }
    }
}
