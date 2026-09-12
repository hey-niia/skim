import Foundation
@preconcurrency import WebKit

enum SiteMetadataFetcher {
    static let script = """
    (function() {
        const og = document.querySelector('meta[property="og:site_name"]');
        if (og && og.content && og.content.trim()) return og.content.trim();
        let title = document.title || '';
        title = title.split(/\\s[-|\\u2013\\u2014]\\s/)[0].trim();
        return title;
    })();
    """

    @MainActor
    static func fetchName(for url: URL) async -> String? {
        let loader = OffscreenLoader()
        guard let raw = try? await loader.load(url: url, script: script) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
