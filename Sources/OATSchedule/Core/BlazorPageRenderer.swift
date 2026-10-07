import Foundation
import WebKit

@MainActor
final class BlazorPageRenderer: NSObject, WKNavigationDelegate {
    enum Mode {
        case navigation
        case changes
    }

    private struct DOMSnapshot: Decodable {
        let html: String
        let text: String
        let tableRows: Int
        let dateCount: Int
    }

    private let webView: WKWebView
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var navigationTimeoutTask: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.isHidden = true
    }

    func render(url: URL, mode: Mode) async throws -> String {
        await NetworkDiagnosticsStore.shared.recordAppEvent(
            "BLAZOR RENDER START",
            details: "URL: \(url.absoluteString) · mode=\(mode == .changes ? "changes" : "navigation")"
        )

        try await navigate(to: url)
        let html = try await waitForRenderedDOM(mode: mode)

        let summary = try? await snapshot()
        await NetworkDiagnosticsStore.shared.recordAppEvent(
            "BLAZOR DOM READY",
            details: """
            URL: \(url.absoluteString)
            HTML chars: \(html.count)
            table rows: \(summary?.tableRows ?? 0)
            date markers: \(summary?.dateCount ?? 0)
            """
        )

        return html
    }

    private func navigate(to url: URL) async throws {
        guard navigationContinuation == nil else {
            throw URLError(.cannotLoadFromNetwork)
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 15
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("ru-RU,ru;q=0.9,en;q=0.6", forHTTPHeaderField: "Accept-Language")

        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation

            navigationTimeoutTask?.cancel()
            navigationTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.finishNavigation(.failure(URLError(.timedOut)))
            }

            webView.load(request)
        }
    }

    private func waitForRenderedDOM(mode: Mode) async throws -> String {
        var latestHTML = ""
        var previousSignature = ""
        var stablePolls = 0

        let maxPolls = mode == .changes ? 34 : 20

        for poll in 0..<maxPolls {
            let current = try await snapshot()
            latestHTML = current.html

            let signature = "\(current.html.count)|\(current.text.count)|\(current.tableRows)|\(current.dateCount)"
            if signature == previousSignature {
                stablePolls += 1
            } else {
                previousSignature = signature
                stablePolls = 0
            }

            let normalizedText = current.text.lowercased()
            let hasChangeTable = current.tableRows > 1
                && normalizedText.contains("групп")
                && (normalizedText.contains("причин") || normalizedText.contains("дисциплин"))

            let explicitlyEmpty = [
                "изменений нет",
                "нет изменений",
                "изменения отсутствуют",
                "данных нет"
            ].contains { normalizedText.contains($0) }

            switch mode {
            case .changes:
                if hasChangeTable && stablePolls >= 1 {
                    return latestHTML
                }
                if poll >= 8 && explicitlyEmpty && stablePolls >= 2 {
                    return latestHTML
                }
            case .navigation:
                if poll >= 4 && current.dateCount > 0 && stablePolls >= 1 {
                    return latestHTML
                }
                if hasChangeTable && stablePolls >= 1 {
                    return latestHTML
                }
                if poll >= 12 && stablePolls >= 3 {
                    return latestHTML
                }
            }

            try await Task.sleep(for: .milliseconds(300))
        }

        guard !latestHTML.isEmpty else {
            throw AppFailure.noData
        }

        return latestHTML
    }

    private func snapshot() async throws -> DOMSnapshot {
        let script = #"""
        (() => {
          const html = document.documentElement ? document.documentElement.outerHTML : "";
          const text = document.body ? document.body.innerText : "";
          const tableRows = document.querySelectorAll("table tr").length;
          const dateCount = (text.match(/\b\d{1,2}\.\d{1,2}\.\d{4}\b/g) || []).length;
          return JSON.stringify({ html, text, tableRows, dateCount });
        })();
        """#

        guard let json = try await webView.evaluateJavaScript(script) as? String,
              let data = json.data(using: .utf8)
        else {
            throw AppFailure.badResponse
        }

        return try JSONDecoder().decode(DOMSnapshot.self, from: data)
    }

    private func finishNavigation(_ result: Result<Void, Error>) {
        guard let continuation = navigationContinuation else { return }

        navigationContinuation = nil
        navigationTimeoutTask?.cancel()
        navigationTimeoutTask = nil

        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishNavigation(.success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finishNavigation(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finishNavigation(.failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finishNavigation(.failure(URLError(.networkConnectionLost)))
    }
}
