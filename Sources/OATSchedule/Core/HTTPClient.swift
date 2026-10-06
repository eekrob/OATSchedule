import Foundation
import OSLog

struct HTTPClient {
    private let session: URLSession
    private let diagnostics: NetworkDiagnosticsStore?
    private let logger = Logger(subsystem: "ru.oat.schedule", category: "network")

    init(session: URLSession? = nil, diagnostics: NetworkDiagnosticsStore? = nil) {
        self.diagnostics = diagnostics
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 9
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "ru-RU,ru;q=0.9,en;q=0.8",
            "Cache-Control": "no-cache"
        ]
        self.session = session ?? URLSession(configuration: configuration)
    }

    func html(from url: URL) async throws -> String {
        var lastError: Error = AppFailure.badResponse

        for attemptIndex in 0..<2 {
            let attempt = attemptIndex + 1
            do {
                let (data, rawResponse) = try await session.data(from: url)
                guard let response = rawResponse as? HTTPURLResponse else {
                    await diagnostics?.recordTransportError(url: url, error: AppFailure.badResponse, attempt: attempt)
                    throw AppFailure.badResponse
                }

                let decoded = decode(data)
                await diagnostics?.recordHTTP(
                    requestedURL: url,
                    response: response,
                    data: data,
                    decodedBody: decoded.text,
                    encoding: decoded.encoding,
                    attempt: attempt
                )

                guard (200..<300).contains(response.statusCode) else {
                    if attemptIndex == 0,
                       response.statusCode == 408 || response.statusCode == 429 || response.statusCode >= 500 {
                        try await Task.sleep(for: .milliseconds(600))
                        continue
                    }
                    throw AppFailure.http(response.statusCode)
                }

                guard let html = decoded.text else { throw AppFailure.badResponse }
                return html
            } catch let error as AppFailure {
                logger.error("HTTP response failed: \(error.localizedDescription, privacy: .public)")
                throw error
            } catch {
                lastError = error
                await diagnostics?.recordTransportError(url: url, error: error, attempt: attempt)
                if attemptIndex == 0 { try? await Task.sleep(for: .milliseconds(450)) }
            }
        }

        logger.error("Request failed after retries: \(lastError.localizedDescription, privacy: .public)")
        logger.debug("Underlying network detail: \(lastError.localizedDescription, privacy: .private)")
        throw AppFailure.network
    }

    func recordParser(stage: String, url: URL, summary: String) async {
        await diagnostics?.recordParser(stage: stage, url: url, summary: summary)
    }

    private func decode(_ data: Data) -> (text: String?, encoding: String?) {
        if let value = String(data: data, encoding: .utf8) {
            return (value, "utf-8")
        }
        if let value = String(data: data, encoding: .windowsCP1251) {
            return (value, "windows-1251")
        }
        return (nil, nil)
    }
}
