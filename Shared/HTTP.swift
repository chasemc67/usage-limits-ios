import Foundation

struct HTTPResult: Sendable {
    let status: Int
    let data: Data
    /// Raw header fields as returned by URLSession.
    let headers: [String: String]

    var isSuccess: Bool { (200..<300).contains(status) }

    var json: JSONValue? { try? JSONValue.parse(data) }

    func header(_ name: String) -> String? {
        let lowered = name.lowercased()
        return headers.first { $0.key.lowercased() == lowered }?.value
    }

    /// A short human-readable reason extracted from an error body.
    var errorSummary: String? {
        if let json {
            let candidates: [JSONValue] = [
                json["error"]["message"], json["error_description"], json["message"],
                json["detail"], json["error"],
            ]
            for candidate in candidates {
                if let text = candidate.nonEmptyString { return String(text.prefix(140)) }
            }
        }
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("<") { return nil } // HTML error pages (e.g. Cloudflare) aren't useful
        return String(text.prefix(140))
    }

    func serviceError() -> ServiceError {
        .http(status, errorSummary)
    }
}

enum HTTP {
    /// Cookie-less session: we always set Cookie headers explicitly so the app and
    /// widget behave identically and nothing leaks between services.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    static let browserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static func request(_ url: URL,
                        method: String = "GET",
                        headers: [String: String] = [:],
                        jsonBody: [String: String]? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = (try? JSONEncoder().encode(jsonBody)) ?? Data("{}".utf8)
        }
        return request
    }

    static func send(_ request: URLRequest) async throws -> HTTPResult {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse("not an HTTP response")
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key] = value
            }
        }
        return HTTPResult(status: http.statusCode, data: data, headers: headers)
    }
}

enum Money {
    static func dollars(cents: Double) -> String {
        String(format: "$%.2f", cents / 100)
    }
}

enum PercentText {
    /// Extracts the first "NN%" / "NN.N%" value from text.
    static func parse(_ text: String?) -> Double? {
        guard let text,
              let range = text.range(of: #"(\d+(?:\.\d+)?)\s*%"#, options: .regularExpression) else { return nil }
        let match = text[range].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        return Double(match)
    }
}
