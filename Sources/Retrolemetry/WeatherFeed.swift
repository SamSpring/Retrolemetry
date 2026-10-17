import Foundation

enum WeatherFeedFailure: Error {
    case http(Int)
    case invalidResponse

    static func status(for error: Error) -> String {
        if case let Self.http(code) = error { return "WEATHER PROVIDER // HTTP \(code)" }
        if error is DecodingError { return "WEATHER DATA INCOMPLETE" }
        if let error = error as? URLError { return "WEATHER CONNECTION // \(error.code.rawValue)" }
        return "WEATHER FEED UNAVAILABLE"
    }

    static func canRetry(_ error: Error) -> Bool {
        if case let Self.http(code) = error { return [500, 502, 503, 504].contains(code) }
        guard let error = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed].contains(error.code)
    }
}

enum LocalWeatherFeed {
    static func url(latitude: Double, longitude: Double) throws -> URL {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw URLError(.badURL)
        }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    /// At most three attempts, with no polling loop or persistent retry timer.
    static func fetch(latitude: Double, longitude: Double, session: URLSession = .shared,
                      retryDelays: [Double] = [3, 12]) async throws -> OpenMeteoResponse {
        let url = try url(latitude: latitude, longitude: longitude)
        let delays = Array(retryDelays.prefix(2))
        for attempt in 0...delays.count {
            try Task.checkCancellation()
            do {
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw WeatherFeedFailure.invalidResponse }
                guard response.statusCode == 200 else { throw WeatherFeedFailure.http(response.statusCode) }
                return try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            } catch {
                try Task.checkCancellation()
                guard attempt < delays.count, WeatherFeedFailure.canRetry(error), delays[attempt].isFinite else { throw error }
                try await Task.sleep(nanoseconds: UInt64(max(0, min(60, delays[attempt])) * 1_000_000_000))
            }
        }
        throw WeatherFeedFailure.invalidResponse
    }
}
