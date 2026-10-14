import Foundation
import SwiftUI

enum RadarRegion: String, CaseIterable, Identifiable {
    case israel, northAmerica, europe
    var id: String { rawValue }
    var title: String {
        switch self { case .israel: "Israel"; case .northAmerica: "North America"; case .europe: "Europe" }
    }
    var screenTitle: String {
        switch self { case .israel: "ISRAEL"; case .northAmerica: "N AMERICA"; case .europe: "EUROPE" }
    }
    var sites: [RadarWeatherSite] {
        switch self {
        case .israel: RadarWeatherSite.all
        case .northAmerica: [
            .init(name: "SEATTLE", latitude: 47.6062, longitude: -122.3321),
            .init(name: "LOS ANGELES", latitude: 34.0522, longitude: -118.2437),
            .init(name: "CHICAGO", latitude: 41.8781, longitude: -87.6298),
            .init(name: "NEW YORK", latitude: 40.7128, longitude: -74.0060),
            .init(name: "TORONTO", latitude: 43.6532, longitude: -79.3832),
            .init(name: "MEXICO CITY", latitude: 19.4326, longitude: -99.1332)
        ]
        case .europe: [
            .init(name: "LONDON", latitude: 51.5074, longitude: -0.1278),
            .init(name: "PARIS", latitude: 48.8566, longitude: 2.3522),
            .init(name: "BERLIN", latitude: 52.5200, longitude: 13.4050),
            .init(name: "MADRID", latitude: 40.4168, longitude: -3.7038),
            .init(name: "ROME", latitude: 41.9028, longitude: 12.4964),
            .init(name: "WARSAW", latitude: 52.2297, longitude: 21.0122)
        ]
        }
    }
}

enum WeatherRegionSelection: String, CaseIterable, Identifiable {
    case automatic, israel, northAmerica, europe
    static let preferenceKey = "DockTelemetry.weatherRadarRegion"
    static let changed = Notification.Name("Retrolemetry.weatherRadarRegionChanged")
    var id: String { rawValue }
    var title: String { self == .automatic ? "Automatic (location)" : (RadarRegion(rawValue: rawValue)?.title ?? "Automatic") }

    func resolve(coordinate: GlobeCoordinate?) -> RadarRegion? {
        if self != .automatic { return RadarRegion(rawValue: rawValue) }
        guard let coordinate else { return nil }
        let lat = coordinate.latitude, lon = coordinate.longitude
        // Local coverage tests: no reverse-geocoding service or extra permission.
        if (29.3...33.6).contains(lat), (34...36).contains(lon) { return .israel }
        if (8...85).contains(lat), (-170 ... -49).contains(lon) { return .northAmerica }
        if (34...72).contains(lat), (-25...45).contains(lon) { return .europe }
        return nil
    }
}

struct WeatherRegionPicker: View {
    @AppStorage(WeatherRegionSelection.preferenceKey) private var selection = WeatherRegionSelection.automatic.rawValue
    var body: some View {
        Picker("Map region", selection: $selection) {
            ForEach(WeatherRegionSelection.allCases) { Text($0.title).tag($0.rawValue) }
        }
        .onChange(of: selection) {
            NotificationCenter.default.post(name: WeatherRegionSelection.changed, object: nil)
        }
    }
}
