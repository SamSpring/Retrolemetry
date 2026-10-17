import XCTest
@testable import Retrolemetry

final class WeatherFeedTests: XCTestCase {
    private let fixture = Data("""
    {"current":{"temperature_2m":24.1,"apparent_temperature":25.0,"relative_humidity_2m":58,"precipitation":0,"weather_code":2,"wind_speed_10m":12},
     "hourly":{"time":[1792231200,1792234800],"temperature_2m":[24.1,23.8],"precipitation_probability":[5,10],"weather_code":[2,2]},
     "daily":{"time":[1792184400],"weather_code":[2],"temperature_2m_max":[25.0],"temperature_2m_min":[19.1],"precipitation_probability_max":[10]}}
    """.utf8)

    private func session(statuses: [Int], data: Data) -> URLSession {
        WeatherFeedStub.reset(statuses, data: data)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WeatherFeedStub.self]
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    func testTransientProviderFailureRecoversAndDecodesForecast() async throws {
        let session = session(statuses: [503, 200], data: fixture)
        defer { session.invalidateAndCancel() }
        let payload = try await LocalWeatherFeed.fetch(latitude: 0, longitude: 0, session: session, retryDelays: [0, 0])
        XCTAssertEqual(WeatherFeedStub.calls, 2)
        XCTAssertEqual(payload.current.temperature2m, 24.1)
        XCTAssertEqual(payload.hourly.temperature2m, [24.1, 23.8])
        XCTAssertEqual(payload.daily.temperature2mMin, [19.1])
    }

    func testPersistentFailureIsBoundedToThreeAttempts() async {
        let session = session(statuses: [503, 503, 503, 200], data: fixture)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await LocalWeatherFeed.fetch(latitude: 0, longitude: 0, session: session, retryDelays: [0, 0, 0, 0])
            XCTFail("Persistent server failure must not be accepted")
        } catch {
            XCTAssertEqual(WeatherFeedFailure.status(for: error), "WEATHER PROVIDER // HTTP 503")
        }
        XCTAssertEqual(WeatherFeedStub.calls, 3)
    }

    func testInvalidPayloadDoesNotLoopOrInventReadings() async {
        let session = session(statuses: [200, 200], data: Data("{}".utf8))
        defer { session.invalidateAndCancel() }
        do {
            _ = try await LocalWeatherFeed.fetch(latitude: 0, longitude: 0, session: session, retryDelays: [0, 0])
            XCTFail("Missing weather readings must not become zeros")
        } catch {
            XCTAssertEqual(WeatherFeedFailure.status(for: error), "WEATHER DATA INCOMPLETE")
        }
        XCTAssertEqual(WeatherFeedStub.calls, 1)
    }

    func testCancellationStopsBackoffAndFurtherRequests() async throws {
        let session = session(statuses: [503, 200], data: fixture)
        defer { session.invalidateAndCancel() }
        let task = Task { try await LocalWeatherFeed.fetch(latitude: 0, longitude: 0, session: session, retryDelays: [30, 30]) }
        for _ in 0..<50 where WeatherFeedStub.calls == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(WeatherFeedStub.calls, 1)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request must stop") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(WeatherFeedStub.calls, 1)
    }

    func testRequestAndPrivacySafeErrorContract() throws {
        let url = try LocalWeatherFeed.url(latitude: 0, longitude: 0)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.open-meteo.com")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "forecast_days" }?.value, "7")
        XCTAssertFalse(query.contains { $0.name == "token" || $0.name == "apikey" })
        XCTAssertThrowsError(try LocalWeatherFeed.url(latitude: .nan, longitude: 0))
        XCTAssertThrowsError(try LocalWeatherFeed.url(latitude: 91, longitude: 0))
        XCTAssertFalse(WeatherFeedFailure.canRetry(WeatherFeedFailure.http(429)))
        XCTAssertFalse(WeatherFeedFailure.canRetry(WeatherFeedFailure.http(403)))
        XCTAssertFalse(WeatherFeedFailure.canRetry(URLError(.cancelled)))
        XCTAssertEqual(WeatherFeedFailure.status(for: URLError(.timedOut)), "WEATHER CONNECTION // -1001")
    }
}

private final class WeatherFeedStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var statuses: [Int] = []
    nonisolated(unsafe) private static var data = Data()
    nonisolated(unsafe) private static var count = 0
    static var calls: Int { lock.lock(); defer { lock.unlock() }; return count }

    static func reset(_ statuses: [Int], data: Data) {
        lock.lock(); defer { lock.unlock() }
        self.statuses = statuses; self.data = data; count = 0
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let code = Self.statuses.isEmpty ? 503 : Self.statuses.removeFirst()
        let data = Self.data
        Self.count += 1
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
