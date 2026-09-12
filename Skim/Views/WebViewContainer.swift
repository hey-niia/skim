import SwiftUI
@preconcurrency import WebKit

struct WebViewContainer: NSViewRepresentable {
    let url: URL
    @Binding var reloadToken: Int
    var onWebViewReady: (WKWebView) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.load(URLRequest(url: url))
        context.coordinator.lastURL = url
        onWebViewReady(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastURL != url {
            webView.load(URLRequest(url: url))
            context.coordinator.lastURL = url
        }
        if context.coordinator.lastReloadToken != reloadToken {
            webView.reload()
            context.coordinator.lastReloadToken = reloadToken
        }
    }

    final class Coordinator {
        var lastURL: URL?
        var lastReloadToken: Int = 0
    }
}
