import Foundation
import OSLog

struct HTTPClient {
    private let session: URLSession
    private let logger = Logger(subsystem: "ru.oat.schedule", category: "network")

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.httpAdditionalHeaders = ["User-Agent": "OATSchedule-iOS/1.0 (student timetable)", "Accept": "text/html,application/xhtml+xml"]
        self.session = session ?? URLSession(configuration: configuration)
    }

    func html(from url: URL, timeout: TimeInterval? = nil, maxAttempts: Int = 3) async throws -> String {
        var lastError: Error = AppFailure.badResponse
        for attempt in 0..<max(1, maxAttempts) {
            do {
                var request = URLRequest(url: url)
                if let timeout { request.timeoutInterval = timeout }
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw AppFailure.badResponse }
                guard (200..<300).contains(response.statusCode) else {
                    if attempt + 1 < maxAttempts, response.statusCode == 408 || response.statusCode == 429 || response.statusCode >= 500 {
                        try await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
                        continue
                    }
                    throw AppFailure.http(response.statusCode)
                }
                guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) else { throw AppFailure.badResponse }
                return html
            } catch let error as AppFailure {
                logger.error("HTTP response failed: \(error.localizedDescription, privacy: .public)")
                throw error
            } catch {
                lastError = error
                if attempt + 1 < maxAttempts { try await Task.sleep(for: .milliseconds(350 * (attempt + 1))) }
            }
        }
        logger.error("Request failed after retries: \(lastError.localizedDescription, privacy: .public)")
        logger.debug("Underlying network detail: \(lastError.localizedDescription, privacy: .private)")
        throw AppFailure.network
    }
}
