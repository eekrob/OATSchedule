import Foundation
import SwiftSoup

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
        let structure = pageStructureSummary(body)
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
        page structure:
        \(structure)

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


    private func pageStructureSummary(_ body: String) -> String {
        guard !body.isEmpty else { return "<empty>" }
        do {
            let doc = try SwiftSoup.parse(body)
            var lines: [String] = []

            let timetableLinks = try doc.select("a[href]").array().compactMap { element -> String? in
                let href = try element.attr("href")
                guard href.localizedCaseInsensitiveContains("timetable")
                    || href.localizedCaseInsensitiveContains("group")
                    || href.localizedCaseInsensitiveContains("class")
                else { return nil }
                let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                return "A text=[\(text)] href=[\(href)]"
            }
            lines.append("relevant anchors: \(timetableLinks.count)")
            lines.append(contentsOf: timetableLinks.prefix(40))

            let forms = try doc.select("form").array()
            lines.append("forms: \(forms.count)")
            for form in forms.prefix(12) {
                let action = try form.attr("action")
                let method = try form.attr("method")
                let id = try form.attr("id")
                let klass = try form.attr("class")
                lines.append("FORM action=[\(action)] method=[\(method)] id=[\(id)] class=[\(klass)]")
            }

            let selects = try doc.select("select").array()
            lines.append("selects: \(selects.count)")
            for select in selects.prefix(12) {
                let id = try select.attr("id")
                let name = try select.attr("name")
                let klass = try select.attr("class")
                lines.append("SELECT id=[\(id)] name=[\(name)] class=[\(klass)]")
                let options = try select.select("option").array()
                for option in options.prefix(30) {
                    let value = try option.attr("value")
                    let text = try option.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    lines.append("  OPTION text=[\(text)] value=[\(value)]")
                }
            }

            let interactive = try doc.select("button, [onclick], [data-href], [data-url]").array()
            let relevantInteractive = try interactive.compactMap { element -> String? in
                let onclick = try element.attr("onclick")
                let dataHref = try element.attr("data-href")
                let dataURL = try element.attr("data-url")
                let value = try element.attr("value")
                let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                let combined = [onclick, dataHref, dataURL, value, text].joined(separator: " ")
                guard combined.localizedCaseInsensitiveContains("timetable")
                    || combined.localizedCaseInsensitiveContains("group")
                    || combined.localizedCaseInsensitiveContains("class")
                    || combined.localizedCaseInsensitiveContains("распис")
                    || combined.localizedCaseInsensitiveContains("груп")
                else { return nil }
                return "UI tag=[\(element.tagName())] text=[\(text)] onclick=[\(onclick)] data-href=[\(dataHref)] data-url=[\(dataURL)] value=[\(value)]"
            }
            lines.append("relevant interactive elements: \(relevantInteractive.count)")
            lines.append(contentsOf: relevantInteractive.prefix(40))

            let scripts = try doc.select("script").array()
            var scriptHits: [String] = []
            for script in scripts {
                let src = try script.attr("src")
                if !src.isEmpty,
                   src.localizedCaseInsensitiveContains("timetable")
                    || src.localizedCaseInsensitiveContains("schedule")
                    || src.localizedCaseInsensitiveContains("group") {
                    scriptHits.append("SCRIPT src=[\(src)]")
                }

                let code = try script.html()
                guard code.localizedCaseInsensitiveContains("timetable")
                    || code.localizedCaseInsensitiveContains("group")
                    || code.localizedCaseInsensitiveContains("fetch(")
                    || code.localizedCaseInsensitiveContains("$.ajax")
                else { continue }

                let compact = code
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                scriptHits.append("SCRIPT inline=[\(String(compact.prefix(1200)))]")
            }
            lines.append("relevant scripts: \(scriptHits.count)")
            lines.append(contentsOf: scriptHits.prefix(12))

            return lines.isEmpty ? "<none>" : lines.joined(separator: "\n")
        } catch {
            return "structure parse failed: \(error.localizedDescription)"
        }
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
