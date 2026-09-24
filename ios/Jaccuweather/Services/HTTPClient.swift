import Foundation

enum HTTPClientError: LocalizedError {
    case badStatus(Int, String?)
    case decoding(Error)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .badStatus(429, _):
            return "Upstream rate limited (HTTP 429). Try again in a minute."
        case .badStatus(let code, let body):
            if let body, !body.isEmpty { return "HTTP \(code): \(body)" }
            return "HTTP \(code)"
        case .decoding(let error):
            return "Decode failed: \(error.localizedDescription)"
        case .timedOut:
            return "The request timed out after 30 seconds."
        }
    }
}

private actor ResponseCache {
    static let shared = ResponseCache()
    private var entries: [String: (expires: Date, data: Data)] = [:]

    func data(for key: String) -> Data? {
        guard let entry = entries[key] else { return nil }
        if entry.expires < Date() {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.data
    }

    func store(_ data: Data, for key: String, ttl: TimeInterval) {
        entries[key] = (Date().addingTimeInterval(ttl), data)
    }
}

enum HTTPClient {
    /// Forecast matches the Worker’s 10-minute cache; geocoding matches the 1-hour cache.
    private static func cacheTTL(for url: URL) -> TimeInterval? {
        let host = url.host ?? ""
        if host.contains("ensemble-api.open-meteo.com") { return 600 }
        if host.contains("geocoding-api.open-meteo.com") { return 3600 }
        return nil
    }

    static func getData(
        _ url: URL,
        extraHeaders: [String: String] = [:],
        userAgent: String = Secrets.openMeteoUserAgent,
        useCache: Bool = true
    ) async throws -> Data {
        let cacheKey = url.absoluteString
        if useCache, let ttl = cacheTTL(for: url), let cached = await ResponseCache.shared.data(for: cacheKey) {
            return cached
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        extraHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let maxRetries = 2
        var attempt = 0
        while true {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    if http.statusCode == 429 && attempt < maxRetries {
                        let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                        let wait = retryAfter ?? pow(2.0, Double(attempt))
                        attempt += 1
                        try await Task.sleep(nanoseconds: UInt64(min(wait, 8) * 1_000_000_000))
                        continue
                    }
                    let snippet = String(data: data.prefix(180), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    throw HTTPClientError.badStatus(http.statusCode, snippet)
                }
                if useCache, let ttl = cacheTTL(for: url) {
                    await ResponseCache.shared.store(data, for: cacheKey, ttl: ttl)
                }
                return data
            } catch let error as HTTPClientError {
                throw error
            } catch let error as URLError where error.code == .timedOut {
                throw HTTPClientError.timedOut
            }
        }
    }

    static func getJSONObject(_ url: URL, extraHeaders: [String: String] = [:], userAgent: String = Secrets.openMeteoUserAgent) async throws -> Any {
        let data = try await getData(url, extraHeaders: extraHeaders, userAgent: userAgent)
        return try JSONSerialization.jsonObject(with: data)
    }

    static func getJSON<T: Decodable>(
        _ url: URL,
        as type: T.Type,
        extraHeaders: [String: String] = [:],
        userAgent: String = Secrets.openMeteoUserAgent
    ) async throws -> T {
        let data = try await getData(url, extraHeaders: extraHeaders, userAgent: userAgent)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HTTPClientError.decoding(error)
        }
    }
}
