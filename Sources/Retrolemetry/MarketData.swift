import Foundation
import Security

struct MarketQuote: Identifiable, Sendable {
    let symbol: String
    let price: Double
    let change: Double
    let percentChange: Double
    let high: Double
    let low: Double
    let open: Double
    let previousClose: Double
    let tradeTime: Date

    var id: String { symbol }
}

struct FXRatePoint: Identifiable, Sendable {
    let date: Date
    let rate: Double
    var id: Date { date }
}

enum MarketTimeframe: String, CaseIterable, Sendable {
    case today
    case week
    case month
    case year

    var label: String {
        switch self {
        case .today: "TODAY"
        case .week: "1 WEEK"
        case .month: "1 MONTH"
        case .year: "1 YEAR"
        }
    }

    var next: MarketTimeframe {
        let values = Self.allCases
        let index = values.firstIndex(of: self) ?? 0
        return values[(index + 1) % values.count]
    }

    var yahooRange: String {
        switch self {
        case .today: "1d"
        case .week: "5d"
        case .month: "1mo"
        case .year: "1y"
        }
    }

    var yahooInterval: String {
        switch self {
        case .today: "5m"
        case .week: "30m"
        case .month: "1d"
        case .year: "1wk"
        }
    }

    var refreshInterval: TimeInterval {
        switch self {
        case .today: 120
        case .week: 600
        case .month: 1_800
        case .year: 3_600
        }
    }
}

enum MarketFeedState: Equatable {
    case needsAPIKey
    case loading
    case live(Date)
    case stale(Date)
    case failed(String)

    var label: String {
        switch self {
        case .needsAPIKey: "API KEY REQUIRED"
        case .loading: "CONNECTING"
        case .live: "LIVE"
        case .stale: "STALE"
        case .failed: "FEED ERROR"
        }
    }
}

extension Notification.Name {
    static let marketConfigurationDidChange = Notification.Name("Retrolemetry.marketConfigurationDidChange")
}

enum MarketKeychain {
    private static let service = "io.github.SamSpring.Retrolemetry.finnhub"
    private static let account = "api-token"

    static func apiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    static func save(apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete()
            return
        }
        let data = Data(trimmed.utf8)
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = lookup
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
        NotificationCenter.default.post(name: .marketConfigurationDidChange, object: nil)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        NotificationCenter.default.post(name: .marketConfigurationDidChange, object: nil)
    }

    enum KeychainError: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .status(let status):
                SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
            }
        }
    }
}

enum MarketSymbols {
    static let defaultValue = "OKLO, RGTI, NXE, QUBT, QBTS"

    static func parse(_ value: String) -> [String] {
        var seen = Set<String>()
        return value
            .components(separatedBy: CharacterSet(charactersIn: ",; \n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(12)
            .map { $0 }
    }
}

struct MarketClockZone: Identifiable, Hashable {
    let id: String
    let title: String
    let shortTitle: String

    static let options: [MarketClockZone] = [
        .init(id: "America/New_York", title: "Florida / New York", shortTitle: "FLORIDA"),
        .init(id: "America/Los_Angeles", title: "Los Angeles", shortTitle: "LA"),
        .init(id: "Europe/London", title: "London", shortTitle: "LONDON"),
        .init(id: "Asia/Jerusalem", title: "Tel Aviv", shortTitle: "TEL AVIV"),
        .init(id: "Europe/Paris", title: "Paris", shortTitle: "PARIS"),
        .init(id: "Europe/Berlin", title: "Berlin", shortTitle: "BERLIN"),
        .init(id: "Asia/Dubai", title: "Dubai", shortTitle: "DUBAI"),
        .init(id: "Asia/Tokyo", title: "Tokyo", shortTitle: "TOKYO"),
        .init(id: "Asia/Hong_Kong", title: "Hong Kong", shortTitle: "HONG KONG"),
        .init(id: "Asia/Singapore", title: "Singapore", shortTitle: "SINGAPORE"),
        .init(id: "Australia/Sydney", title: "Sydney", shortTitle: "SYDNEY"),
        .init(id: "UTC", title: "UTC", shortTitle: "UTC")
    ]

    static func option(for identifier: String) -> MarketClockZone {
        options.first(where: { $0.id == identifier }) ?? options[0]
    }
}

@MainActor
final class MarketModel: ObservableObject {
    @Published private(set) var quotes: [String: MarketQuote] = [:]
    @Published private(set) var histories: [String: [Double]] = [:]
    @Published private(set) var rangeHistories: [String: [MarketTimeframe: [Double]]] = [:]
    @Published private(set) var loadingRanges: Set<String> = []
    @Published private(set) var unavailableRanges: Set<String> = []
    @Published private(set) var symbols: [String] = MarketSymbols.parse(MarketSymbols.defaultValue)
    @Published private(set) var state: MarketFeedState = .needsAPIKey
    @Published private(set) var usdIlsHistory: [FXRatePoint] = []
    @Published private(set) var usdIlsUpdatedAt: Date?

    private var refreshTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private let isPreview: Bool
    private var cachedAPIKey: String?
    private var attemptedKeychainLoad = false
    private var rangeUpdatedAt: [String: Date] = [:]

    init(preview: Bool = false) {
        isPreview = preview
        if preview {
            let prices = ["OKLO": 73.42, "RGTI": 18.63, "NXE": 7.91, "QUBT": 14.28, "QBTS": 17.54]
            for (index, symbol) in symbols.enumerated() {
                let price = prices[symbol] ?? 10
                quotes[symbol] = MarketQuote(
                    symbol: symbol,
                    price: price,
                    change: index.isMultiple(of: 2) ? price * 0.018 : -price * 0.012,
                    percentChange: index.isMultiple(of: 2) ? 1.8 : -1.2,
                    high: price * 1.035,
                    low: price * 0.965,
                    open: price * 0.984,
                    previousClose: price * 0.982,
                    tradeTime: Date()
                )
                var previewHistory: [Double] = []
                for sample in 0..<36 {
                    let trend = Double(sample) / 2100
                    let wave = sin(Double(sample) * 0.42 + Double(index)) * 0.008
                    previewHistory.append(price * (0.985 + trend + wave))
                }
                histories[symbol] = previewHistory
                rangeHistories[symbol] = Dictionary(uniqueKeysWithValues: MarketTimeframe.allCases.map { timeframe in
                    let count: Int
                    switch timeframe {
                    case .today: count = 36
                    case .week: count = 54
                    case .month: count = 24
                    case .year: count = 52
                    }
                    let values = (0..<count).map { sample in
                        let progress = Double(sample) / Double(max(1, count - 1))
                        let wave = sin(Double(sample) * 0.42 + Double(index)) * 0.018
                        return price * (0.91 + progress * 0.09 + wave)
                    }
                    return (timeframe, values)
                })
            }
            state = .live(Date())
            let calendar = Calendar(identifier: .gregorian)
            for index in 0..<24 {
                let date = calendar.date(byAdding: .day, value: index - 23, to: Date()) ?? Date()
                let rate = 3.24 + sin(Double(index) * 0.42) * 0.035 + Double(index) * 0.0015
                usdIlsHistory.append(FXRatePoint(date: date, rate: rate))
            }
            usdIlsUpdatedAt = Date()
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: .marketConfigurationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let owner = self else { return }
            Task { @MainActor in owner.restart() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        refreshTask?.cancel()
    }

    func start() {
        guard !isPreview else { return }
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(12))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func restart() {
        stop()
        cachedAPIKey = nil
        attemptedKeychainLoad = false
        start()
    }

    func chartValues(for symbol: String, timeframe: MarketTimeframe) -> [Double] {
        if let values = rangeHistories[symbol]?[timeframe], values.count > 1 {
            return values
        }
        return timeframe == .today ? (histories[symbol] ?? []) : []
    }

    func isLoadingChart(for symbol: String, timeframe: MarketTimeframe) -> Bool {
        loadingRanges.contains(rangeKey(symbol, timeframe))
    }

    func isChartUnavailable(for symbol: String, timeframe: MarketTimeframe) -> Bool {
        unavailableRanges.contains(rangeKey(symbol, timeframe))
    }

    func loadChart(for symbol: String, timeframe: MarketTimeframe) async {
        guard !isPreview else { return }
        let key = rangeKey(symbol, timeframe)
        if loadingRanges.contains(key) { return }
        if let updated = rangeUpdatedAt[key], Date().timeIntervalSince(updated) < timeframe.refreshInterval { return }

        loadingRanges.insert(key)
        unavailableRanges.remove(key)
        defer { loadingRanges.remove(key) }
        do {
            let values = try await MarketAPI.yahooChart(symbol: symbol, timeframe: timeframe)
            guard values.count > 1 else {
                unavailableRanges.insert(key)
                rangeUpdatedAt[key] = Date()
                return
            }
            var ranges = rangeHistories[symbol] ?? [:]
            ranges[timeframe] = values
            rangeHistories[symbol] = ranges
            rangeUpdatedAt[key] = Date()
        } catch {
            unavailableRanges.insert(key)
            rangeUpdatedAt[key] = Date()
        }
    }

    private func rangeKey(_ symbol: String, _ timeframe: MarketTimeframe) -> String {
        "\(symbol):\(timeframe.rawValue)"
    }

    private func refresh() async {
        let configured = UserDefaults.standard.string(forKey: "DockTelemetry.marketSymbols") ?? MarketSymbols.defaultValue
        let nextSymbols = MarketSymbols.parse(configured)
        symbols = nextSymbols.isEmpty ? MarketSymbols.parse(MarketSymbols.defaultValue) : nextSymbols

        await refreshExchangeRateIfNeeded()

        if !attemptedKeychainLoad {
            cachedAPIKey = MarketKeychain.apiKey()
            attemptedKeychainLoad = true
        }
        guard let apiKey = cachedAPIKey else {
            state = .needsAPIKey
            return
        }
        if quotes.isEmpty { state = .loading }

        let requestedSymbols = symbols
        let results = await withTaskGroup(of: (String, Result<MarketQuote, Error>).self) { group in
            for symbol in requestedSymbols {
                group.addTask {
                    do {
                        return (symbol, .success(try await MarketAPI.quote(symbol: symbol, apiKey: apiKey)))
                    } catch {
                        return (symbol, .failure(error))
                    }
                }
            }
            var collected: [(String, Result<MarketQuote, Error>)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var successful = 0
        var lastError: Error?
        for (symbol, result) in results {
            switch result {
            case .success(let quote):
                quotes[symbol] = quote
                var samples = histories[symbol] ?? []
                samples.append(quote.price)
                if samples.count > 90 { samples.removeFirst(samples.count - 90) }
                histories[symbol] = samples
                successful += 1
            case .failure(let error):
                lastError = error
            }
        }

        let now = Date()
        if successful == requestedSymbols.count {
            state = .live(now)
        } else if successful > 0 || !quotes.isEmpty {
            state = .stale(now)
        } else {
            state = .failed(lastError?.localizedDescription ?? "No quote data")
        }
    }

    private func refreshExchangeRateIfNeeded() async {
        if let usdIlsUpdatedAt, Date().timeIntervalSince(usdIlsUpdatedAt) < 60 * 60 { return }
        do {
            let points = try await MarketAPI.usdIlsHistory()
            guard !points.isEmpty else { return }
            usdIlsHistory = points
            usdIlsUpdatedAt = Date()
        } catch {
            // Keep the last successful daily reference series if the feed is temporarily unavailable.
        }
    }
}

private enum MarketAPI {
    static func quote(symbol: String, apiKey: String) async throws -> MarketQuote {
        var components = URLComponents(string: "https://finnhub.io/api/v1/quote")!
        components.queryItems = [URLQueryItem(name: "symbol", value: symbol)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        request.setValue(apiKey, forHTTPHeaderField: "X-Finnhub-Token")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MarketAPIError.badResponse
        }
        let payload = try JSONDecoder().decode(FinnhubQuote.self, from: data)
        guard payload.c > 0 else { throw MarketAPIError.noQuote }
        return MarketQuote(
            symbol: symbol,
            price: payload.c,
            change: payload.d,
            percentChange: payload.dp,
            high: payload.h,
            low: payload.l,
            open: payload.o,
            previousClose: payload.pc,
            tradeTime: Date(timeIntervalSince1970: TimeInterval(payload.t))
        )
    }

    static func usdIlsHistory() async throws -> [FXRatePoint] {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(byAdding: .day, value: -35, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var components = URLComponents(string: "https://api.frankfurter.dev/v2/rates")!
        components.queryItems = [
            URLQueryItem(name: "base", value: "USD"),
            URLQueryItem(name: "quotes", value: "ILS"),
            URLQueryItem(name: "from", value: formatter.string(from: start))
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MarketAPIError.badResponse
        }
        let payload = try JSONDecoder().decode([FrankfurterRate].self, from: data)
        return payload.compactMap { item in
            guard item.quote == "ILS", let date = formatter.date(from: item.date) else { return nil }
            return FXRatePoint(date: date, rate: item.rate)
        }
        .sorted { $0.date < $1.date }
        .suffix(24)
        .map { $0 }
    }

    static func yahooChart(symbol: String, timeframe: MarketTimeframe) async throws -> [Double] {
        let safeSymbol = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        var components = URLComponents(string: "https://query2.finance.yahoo.com/v8/finance/chart/\(safeSymbol)")!
        components.queryItems = [
            URLQueryItem(name: "range", value: timeframe.yahooRange),
            URLQueryItem(name: "interval", value: timeframe.yahooInterval)
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12
        request.setValue("Retrolemetry/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MarketAPIError.badResponse
        }
        let payload = try JSONDecoder().decode(YahooChartResponse.self, from: data)
        guard let closes = payload.chart.result?.first?.indicators.quote.first?.close else {
            throw MarketAPIError.noChartData
        }
        return closes.compactMap { $0 }
    }

    private struct FinnhubQuote: Decodable {
        let c: Double
        let d: Double
        let dp: Double
        let h: Double
        let l: Double
        let o: Double
        let pc: Double
        let t: Int
    }

    private struct FrankfurterRate: Decodable {
        let date: String
        let base: String
        let quote: String
        let rate: Double
    }

    private struct YahooChartResponse: Decodable {
        let chart: Chart

        struct Chart: Decodable {
            let result: [Result]?
        }

        struct Result: Decodable {
            let indicators: Indicators
        }

        struct Indicators: Decodable {
            let quote: [Quote]
        }

        struct Quote: Decodable {
            let close: [Double?]
        }
    }

    private enum MarketAPIError: LocalizedError {
        case badResponse
        case noQuote
        case noChartData

        var errorDescription: String? {
            switch self {
            case .badResponse: "Finnhub did not accept the request"
            case .noQuote: "No current quote is available"
            case .noChartData: "No historical chart data is available"
            }
        }
    }
}
