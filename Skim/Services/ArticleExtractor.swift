import Foundation
@preconcurrency import WebKit

enum ArticleExtractor {
    static let headlineScript = """
    (function() {
        const boilerplate = /cookie|privacy|consent|subscri|sign in|log ?in|terms of (service|use)|advertise with|contact us|skip to content|manage preferences|legitimate interest|all rights reserved|download the app/i;

        function extractSrc(img) {
            const src = img.currentSrc || img.src || img.getAttribute('data-src');
            if (!src || !src.startsWith('http')) return null;
            return src;
        }

        // Walk up ancestor levels looking for the nearest container that has an image,
        // rather than guessing by class name — real markup nests the headline link and
        // its thumbnail inside a shared per-item wrapper, sometimes many levels up (NYT's
        // grid cards nest ~6 deep). But a container that wide might no longer be scoped to
        // just this one story — it could be the shared list/grid holding many stories, in
        // which case its "first image" would get wrongly attached to every item in it. So
        // at each level we also count the links inside: as long as it stays low (still
        // basically just this one card), an image found there is trustworthy; the moment
        // it jumps (a few sibling stories' links are now in scope too), stop rather than
        // risk a mismatched photo.
        function findImage(anchor) {
            let img = anchor.querySelector('img[src], img[data-src], img[srcset]');
            if (img) return extractSrc(img);
            let node = anchor.parentElement;
            for (let i = 0; i < 8 && node; i++) {
                if (node.querySelectorAll('a[href]').length > 4) break;
                img = node.querySelector('img[src], img[data-src], img[srcset]');
                if (img) return extractSrc(img);
                node = node.parentElement;
            }
            return null;
        }

        const candidates = [];
        const anchors = document.querySelectorAll('a[href]');
        anchors.forEach(function(a) {
            let text = (a.innerText || a.textContent || '').trim().replace(/\\s+/g, ' ');
            if (!text || text.length < 24 || text.length > 200) return;
            if (boilerplate.test(text)) return;
            const href = a.href;
            if (!href || !href.startsWith('http')) return;
            candidates.push({ title: text, url: href, image: findImage(a) });
        });

        const textCounts = {};
        candidates.forEach(function(c) { textCounts[c.title] = (textCounts[c.title] || 0) + 1; });

        const seenPaths = new Set();
        const results = [];
        candidates.forEach(function(c) {
            if (textCounts[c.title] > 1) return;
            const path = c.url.split('#')[0].split('?')[0];
            if (seenPaths.has(path)) return;
            seenPaths.add(path);
            results.push(c);
        });

        return JSON.stringify(results.slice(0, 40));
    })();
    """

    static let bodyScript = """
    (function() {
        const scope = document.querySelector('article') || document.querySelector('main') || document.querySelector('[role="main"]') || document.body;
        const parts = [];
        scope.querySelectorAll('h1, h2, h3, h4, p, li').forEach(function(node) {
            const text = (node.innerText || node.textContent || '').trim().replace(/\\s+/g, ' ');
            if (text.length > 3) parts.push(text);
        });

        const h1 = document.querySelector('h1');
        const titleText = h1 ? (h1.innerText || h1.textContent || '').trim() : document.title;

        let imageUrl = null;
        const og = document.querySelector('meta[property="og:image"]');
        if (og && og.content) {
            imageUrl = og.content;
        } else {
            const img = scope.querySelector('img[src]');
            if (img) imageUrl = img.currentSrc || img.src;
        }

        return JSON.stringify({ title: titleText, body: parts.join('\\n\\n'), image: imageUrl });
    })();
    """

    /// Extracts headline candidates from a live, already-loaded WKWebView.
    @MainActor
    static func extractHeadlines(from webView: WKWebView) async -> [Headline] {
        guard let raw = try? await webView.evaluateJavaScript(headlineScript) as? String,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([RawHeadline].self, from: data) else {
            return []
        }
        return decoded.map { Headline(title: $0.title, urlString: $0.url, imageURLString: $0.image) }
    }

    /// Loads a URL off-screen and extracts headline candidates from it.
    @MainActor
    static func loadHeadlines(from url: URL) async throws -> [Headline] {
        let loader = OffscreenLoader()
        let raw = try await loader.load(url: url, script: headlineScript)
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([RawHeadline].self, from: data) else {
            return []
        }
        return decoded.map { Headline(title: $0.title, urlString: $0.url, imageURLString: $0.image) }
    }

    /// Loads a URL off-screen and extracts the readable body text + title + a representative image.
    @MainActor
    static func extractArticle(from url: URL) async throws -> (title: String, body: String, imageURLString: String?) {
        let loader = OffscreenLoader()
        let raw = try await loader.load(url: url, script: bodyScript)
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RawArticle.self, from: data) else {
            throw OffscreenLoader.ExtractionError.parsingFailed
        }
        return (decoded.title, decoded.body, decoded.image)
    }

    private struct RawHeadline: Codable {
        let title: String
        let url: String
        let image: String?
    }

    private struct RawArticle: Codable {
        let title: String
        let body: String
        let image: String?
    }
}

/// Loads a URL in a hidden WKWebView just long enough to run an extraction script,
/// returning its raw (JSON-stringified) result.
@MainActor
final class OffscreenLoader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var script: String = ""
    private var didResume = false

    func load(url: URL, script: String) async throws -> String {
        self.script = script
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let config = WKWebViewConfiguration()
            let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1200, height: 2000), configuration: config)
            webView.navigationDelegate = self
            self.webView = webView
            webView.load(URLRequest(url: url))

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self.finish(.failure(ExtractionError.timedOut))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard let raw = try? await webView.evaluateJavaScript(script) as? String else {
                finish(.failure(ExtractionError.parsingFailed))
                return
            }
            finish(.success(raw))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<String, Error>) {
        guard !didResume else { return }
        didResume = true
        switch result {
        case .success(let value):
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
        webView = nil
    }

    enum ExtractionError: Error {
        case parsingFailed
        case timedOut
    }
}
