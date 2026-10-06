import Foundation
import OSLog

struct HTTPClient {
    private let session: URLSession
    private let logger = Logger(subsystem: "ru.oat.schedule", category: "network")

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 9
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = [
            "User-Agent": "OATSchedule-iOS/1.0 (student timetable)",
            "Accept": "text/html,application/xhtml+xml"
        ]
        self.session = session ?? URLSession(configuration: configuration)
    }

    func html(from url: URL) async throws -> String {
        var lastError: Error = AppFailure.badResponse
        for attempt in 0..<2 {
            do {
                let (data, response) = try await session.data(from: url)
                guard let response = response as? HTTPURLResponse else { throw AppFailure.badResponse }
                guard (200..<300).contains(response.statusCode) else {
                    if attempt == 0, response.statusCode == 408 || response.statusCode == 429 || response.statusCode >= 500 {
                        try await Task.sleep(for: .milliseconds(600))
                        continue
                    }
                    throw AppFailure.http(response.statusCode)
                }
                guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) else {
                    throw AppFailure.badResponse
                }
                return html
            } catch let error as AppFailure {
                logger.error("HTTP response failed: \(error.localizedDescription, privacy: .public)")
                throw error
            } catch {
                lastError = error
                if attempt == 0 { try? await Task.sleep(for: .milliseconds(450)) }
            }
        }
        logger.error("Request failed after retries: \(lastError.localizedDescription, privacy: .public)")
        logger.debug("Underlying network detail: \(lastError.localizedDescription, privacy: .private)")
        throw AppFailure.network
    }
}
