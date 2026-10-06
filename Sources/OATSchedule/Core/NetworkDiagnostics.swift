import Foundation

actor NetworkDiagnosticsStore {
    static let shared = NetworkDiagnosticsStore()

    private struct Event {
        let date: Date
        let kind: String
        let details: String
    }

    private var events: [Event] = []
    private let maxEvents = 16

    func recordHTTP(
        requestedURL: URL,
        response: HTTPURLResponse,
        data: Data,
        decodedBody: String?,
        encoding: String?,
        attempt: Int
    ) {
        let body = decodedBody ?? ""
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? "—"
        let server = response.value(forHTTPHeaderField: "Server") ?? "—"
        let cfRay = response.value(forHTTPHeaderField: "CF-RAY") ?? "—"
        let hasCookie = response.value(forHTTPHeaderField: "Set-Cookie") != nil ? "yes (value hidden)" : "no"
        let anchorCount = countOccurrences(of: "<a", in: body)
        let groupLinkCount = countOccurrences(of: "/timetable/groups/", in: body)
        let timetableLinkCount = countOccurrences(of: "/timetable/timetable/", in: body)
        let changesLinkCount = countOccurrences(of: "/timetable/Changes/", in: body)
        let suspiciousMarkers = [
            "cloudflare",
            "captcha",
            "access denied",
            "enable javascript",
            "checking your browser",
            "just a moment"
        ].filter { body.localizedCaseInsensitiveContains($0) }

        let preview = sanitizedPreview(body)
        let details = """
        attempt: \(attempt)
        requested: \(requestedURL.absoluteString)
        final URL: \(response.url?.absoluteString ?? "—")
        HTTP: \(response.statusCode)
        Content-Type: \(contentType)
        Server: \(server)
        CF-RAY: \(cfRay)
        Set-Cookie: \(hasCookie)
        bytes: \(data.count)
        decoded as: \(encoding ?? "failed")
        <a occurrences: \(anchorCount)
        /timetable/groups/: \(groupLinkCount)
        /timetable/timetable/: \(timetableLinkCount)
        /timetable/Changes/: \(changesLinkCount)
        anti-bot markers: \(suspiciousMarkers.isEmpty ? "none" : suspiciousMarkers.joined(separator: ", "))
        response preview:
        \(preview.isEmpty ? "<empty>" : preview)
        """
        append(Event(date: .now, kind: "HTTP", details: details))
    }

    func recordTransportError(url: URL, error: Error, attempt: Int) {
        append(Event(
            date: .now,
            kind: "NETWORK ERROR",
            details: """
            attempt: \(attempt)
            requested: \(url.absoluteString)
            error type: \(String(reflecting: type(of: error)))
            error: \(error.localizedDescription)
            """
        ))
    }

    func recordParser(stage: String, url: URL, summary: String) {
        append(Event(
            date: .now,
            kind: "PARSER · \(stage)",
            details: "URL: \(url.absoluteString)\n\(summary)"
        ))
    }

    func recordAppEvent(_ title: String, details: String) {
        append(Event(date: .now, kind: title, details: details))
    }

    func clear() {
        events.removeAll()
    }

    func report() -> String {
        let formatter = ISO8601DateFormatter()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        let testMode = UserDefaults.standard.bool(forKey: "testMode") ? "YES" : "NO"

        var result = """
        OATSchedule diagnostics
        generated: \(formatter.string(from: .now))
        app: \(appVersion) (\(build))
        OS: \(system)
        locale: \(Locale.current.identifier)
        test mode: \(testMode)
        events: \(events.count)

        """

        if events.isEmpty {
            result += "No network diagnostics recorded yet.\n"
            return result
        }

        for (index, event) in events.enumerated() {
            result += """
            ===== EVENT \(index + 1) · \(event.kind) · \(formatter.string(from: event.date)) =====
            \(event.details)

            """
        }
        return result
    }

    private func append(_ event: Event) {
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    private func countOccurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty, !haystack.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, options: [.caseInsensitive], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }
        return count
    }

    private func sanitizedPreview(_ body: String) -> String {
        let compact = body
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(compact.prefix(1400))
    }
}
