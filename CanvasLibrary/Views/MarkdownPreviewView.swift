//
//  MarkdownPreviewView.swift
//  Canvas Library
//

import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    let isDark: Bool
    let reloadToken: UUID

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastToken != reloadToken
            || context.coordinator.lastMarkdown != markdown
            || context.coordinator.lastDark != isDark {
            context.coordinator.lastToken = reloadToken
            context.coordinator.lastMarkdown = markdown
            context.coordinator.lastDark = isDark
            let html = MarkdownRenderer.htmlDocument(from: markdown, isDark: isDark)
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    final class Coordinator {
        weak var webView: WKWebView?
        var lastToken: UUID?
        var lastMarkdown: String?
        var lastDark: Bool?
    }
}
