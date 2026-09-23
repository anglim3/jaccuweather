import Foundation

enum HTTPClientError: LocalizedError {
    case badStatus(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "HTTP \(code)"
        case .decoding(let error): return "Decode failed: \(error.localizedDescription)"
        }
    }
}

enum HTTPClient {
    /// NWS requires a User-Agent identifying the client. Other public APIs tolerate it.
    static let userAgent = "JaccuweatherPersonal/1.0 (https://github.com/anglim3/jaccuweather)"

    static func getJSON<T: Decodable>(_ url: URL, as type: T.Type, extraHeaders: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        extraHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw HTTPClientError.badStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HTTPClientError.decoding(error)
        }
    }
}
