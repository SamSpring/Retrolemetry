import Foundation
import Combine
import CoreLocation

struct WeatherSnapshot {
    var location = "AWAITING LOCATION"
    var condition = "WEATHER OFFLINE"
    var temperature = 0.0
    var apparentTemperature = 0.0
    var humidity = 0.0
    var windSpeed = 0.0
    var precipitation = 0.0
    var temperatureForecast: [Double] = Array(repeating: 0, count: 12)
    var precipitationForecast: [Double] = Array(repeating: 0, count: 12)
    var updatedAt: Date?
    var status = "LOCATION PERMISSION REQUIRED"
}

@MainActor
final class WeatherModel: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var snapshot = WeatherSnapshot()

    private let locationManager = CLLocationManager()
    private var refreshTimer: Timer?
    private var coordinate: CLLocationCoordinate2D?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        requestLocation()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refreshTimer?.tolerance = 60
    }

    deinit { refreshTimer?.invalidate() }

    private func requestLocation() {
        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways:
            snapshot.status = "LOCATING"
            locationManager.requestLocation()
        case .notDetermined:
            snapshot.status = "REQUESTING LOCATION"
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            snapshot.status = "ENABLE LOCATION IN SYSTEM SETTINGS"
        @unknown default:
            snapshot.status = "LOCATION UNAVAILABLE"
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = location.coordinate
        snapshot.location = String(format: "LOCAL %.2f° %.2f°", location.coordinate.latitude, location.coordinate.longitude)
        refresh()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        snapshot.status = "LOCATION UNAVAILABLE"
    }

    private func refresh() {
        guard let coordinate else {
            requestLocation()
            return
        }
        snapshot.status = "UPDATING FORECAST"

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability"),
            URLQueryItem(name: "forecast_hours", value: "12"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { return }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let payload = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                apply(payload)
            } catch {
                snapshot.status = "WEATHER FEED UNAVAILABLE"
            }
        }
    }

    private func apply(_ payload: OpenMeteoResponse) {
        let temperatures = Array(payload.hourly.temperature2m.prefix(12))
        let precipitation = Array(payload.hourly.precipitationProbability.prefix(12))
        snapshot.condition = weatherCondition(payload.current.weatherCode)
        snapshot.temperature = payload.current.temperature2m
        snapshot.apparentTemperature = payload.current.apparentTemperature
        snapshot.humidity = payload.current.relativeHumidity2m / 100
        snapshot.windSpeed = payload.current.windSpeed10m
        snapshot.precipitation = payload.current.precipitation
        snapshot.temperatureForecast = normalized(temperatures)
        snapshot.precipitationForecast = precipitation.map { min(1, max(0, $0 / 100)) }
        snapshot.updatedAt = Date()
        snapshot.status = "LIVE // OPEN-METEO"
    }

    private func normalized(_ values: [Double]) -> [Double] {
        guard let low = values.min(), let high = values.max() else { return [] }
        let span = max(2, high - low)
        return values.map { 0.12 + (($0 - low) / span) * 0.76 }
    }

    private func weatherCondition(_ code: Int) -> String {
        switch code {
        case 0: "CLEAR SKY"
        case 1, 2: "PARTLY CLOUDY"
        case 3: "OVERCAST"
        case 45, 48: "FOG"
        case 51...57: "DRIZZLE"
        case 61...67: "RAIN"
        case 71...77: "SNOW"
        case 80...82: "RAIN SHOWERS"
        case 85, 86: "SNOW SHOWERS"
        case 95...99: "THUNDERSTORM"
        default: "MIXED CONDITIONS"
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    let current: Current
    let hourly: Hourly

    struct Current: Decodable {
        let temperature2m: Double
        let apparentTemperature: Double
        let relativeHumidity2m: Double
        let precipitation: Double
        let weatherCode: Int
        let windSpeed10m: Double

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity2m = "relative_humidity_2m"
            case precipitation
            case weatherCode = "weather_code"
            case windSpeed10m = "wind_speed_10m"
        }
    }

    struct Hourly: Decodable {
        let temperature2m: [Double]
        let precipitationProbability: [Double]

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case precipitationProbability = "precipitation_probability"
        }
    }
}
