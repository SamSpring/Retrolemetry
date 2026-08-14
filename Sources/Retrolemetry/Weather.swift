import Foundation
import Combine
@preconcurrency import CoreLocation

struct HourlyWeatherPoint {
    let time: Date
    let temperature: Double
    let precipitationChance: Double
    let condition: String
}

struct DailyWeatherPoint {
    let date: Date
    let low: Double
    let high: Double
    let precipitationChance: Double
    let condition: String
}

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
    var hourlyForecast: [HourlyWeatherPoint] = []
    var dailyForecast: [DailyWeatherPoint] = []
    var updatedAt: Date?
    var status = "LOCATION PERMISSION REQUIRED"
}

@MainActor
final class WeatherModel: NSObject, ObservableObject, CLLocationManagerDelegate {
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
            guard let owner = self else { return }
            Task { @MainActor in owner.refresh() }
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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.requestLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        Task { @MainActor [weak self] in self?.applyLocation(latitude: latitude, longitude: longitude) }
    }

    private func applyLocation(latitude: Double, longitude: Double) {
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        snapshot.location = String(format: "LOCAL %.2f° %.2f°", latitude, longitude)
        refresh()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.snapshot.status = "LOCATION UNAVAILABLE" }
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
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
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
        let currentTimestamp = Int(Date().timeIntervalSince1970)
        let hourlyCount = [
            payload.hourly.time.count,
            payload.hourly.temperature2m.count,
            payload.hourly.precipitationProbability.count,
            payload.hourly.weatherCode.count
        ].min() ?? 0
        let validHourlyTimes = payload.hourly.time.prefix(hourlyCount)
        let hourlyStart = validHourlyTimes.firstIndex(where: { $0 >= currentTimestamp - 1800 }) ?? 0
        let hourlyEnd = min(hourlyCount, hourlyStart + 12)
        let hourlyRange = hourlyStart..<hourlyEnd
        let hourlyPoints = hourlyRange.map { index in
            HourlyWeatherPoint(
                time: Date(timeIntervalSince1970: TimeInterval(payload.hourly.time[index])),
                temperature: payload.hourly.temperature2m[index],
                precipitationChance: min(1, max(0, payload.hourly.precipitationProbability[index] / 100)),
                condition: weatherCondition(payload.hourly.weatherCode[index])
            )
        }
        let dailyCount = [
            payload.daily.time.count,
            payload.daily.weatherCode.count,
            payload.daily.temperature2mMax.count,
            payload.daily.temperature2mMin.count,
            payload.daily.precipitationProbabilityMax.count,
            7
        ].min() ?? 0
        let dailyPoints = (0..<dailyCount).map { index in
            DailyWeatherPoint(
                date: Date(timeIntervalSince1970: TimeInterval(payload.daily.time[index])),
                low: payload.daily.temperature2mMin[index],
                high: payload.daily.temperature2mMax[index],
                precipitationChance: min(1, max(0, payload.daily.precipitationProbabilityMax[index] / 100)),
                condition: weatherCondition(payload.daily.weatherCode[index])
            )
        }
        let temperatures = hourlyPoints.map(\.temperature)
        let precipitation = hourlyPoints.map(\.precipitationChance)
        snapshot.condition = weatherCondition(payload.current.weatherCode)
        snapshot.temperature = payload.current.temperature2m
        snapshot.apparentTemperature = payload.current.apparentTemperature
        snapshot.humidity = payload.current.relativeHumidity2m / 100
        snapshot.windSpeed = payload.current.windSpeed10m
        snapshot.precipitation = payload.current.precipitation
        snapshot.temperatureForecast = normalized(temperatures)
        snapshot.precipitationForecast = precipitation
        snapshot.hourlyForecast = hourlyPoints
        snapshot.dailyForecast = dailyPoints
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
    let daily: Daily

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
        let time: [Int]
        let temperature2m: [Double]
        let precipitationProbability: [Double]
        let weatherCode: [Int]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case precipitationProbability = "precipitation_probability"
            case weatherCode = "weather_code"
        }
    }

    struct Daily: Decodable {
        let time: [Int]
        let weatherCode: [Int]
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]
        let precipitationProbabilityMax: [Double]

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case precipitationProbabilityMax = "precipitation_probability_max"
        }
    }
}
