//
//  PDFExporter.swift
//  Canvas Library
//
//  Export / print the current document via WKWebView (preview HTML or source).
//

import AppKit
import Foundation
import PDFKit
import WebKit

enum PDFExporterError: LocalizedError {
    case noContent
    case webViewFailed(String)
    case writeFailed(String)
    case timedOut
    case printFailed

    var errorDescription: String? {
        switch self {
        case .noContent: return "Nothing to export"
        case .webViewFailed(let m): return m
        case .writeFailed(let m): return m
        case .timedOut: return "Timed out while rendering PDF"
        case .printFailed: return "Could not open the print panel"
        }
    }
}

@MainActor
enum PDFExporter {
    private static let pageWidth: CGFloat = 816   // ~letter @ 96dpi
    private static let minHeight: CGFloat = 1056
    private static let defaultTimeout: TimeInterval = 20

    // MARK: - Public API

    /// Markdown → styled HTML → PDF (light theme for print).
    static func exportMarkdown(_ markdown: String, title: String) async throws -> Data {
        let html = MarkdownRenderer.htmlDocument(from: markdown, isDark: false, forPrint: true)
        _ = title
        return try await pdfData(fromHTML: html, settle: 0.2)
    }

    /// Plain source dump as PDF (fallback for canvas when host PDF fails).
    static func exportSource(_ source: String, title: String) async throws -> Data {
        let escaped = escape(source)
        let html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(escape(title))</title>
        <style>
          @page { margin: 0.6in; size: letter; }
          html, body { margin: 0; padding: 0; background: #fff; color: #111; }
          h1 { font: 600 14pt -apple-system, BlinkMacSystemFont, sans-serif; margin: 0 0 12px; }
          pre {
            font: 9.5pt ui-monospace, SFMono-Regular, Menlo, monospace;
            white-space: pre-wrap; word-break: break-word;
            margin: 0; line-height: 1.45;
          }
        </style></head>
        <body><h1>\(escape(title))</h1><pre>\(escaped)</pre></body></html>
        """
        return try await pdfData(fromHTML: html, settle: 0.15)
    }

    /// Render HTML string to PDF data using a window-hosted WKWebView.
    static func pdfData(fromHTML html: String, baseURL: URL? = nil, settle: TimeInterval = 0.25) async throws -> Data {
        try await renderPDF(settle: settle, timeout: defaultTimeout) { webView in
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    /// Load a file URL (e.g. canvas host.html) and create PDF.
    static func pdfData(fromFileURL url: URL, allowingReadAccessTo access: URL, settle: TimeInterval = 1.0) async throws -> Data {
        try await renderPDF(settle: settle, timeout: defaultTimeout) { webView in
            webView.loadFileURL(url, allowingReadAccessTo: access)
        }
    }

    /// Present the system print panel for PDF data.
    static func presentPrintPanel(for data: Data, jobTitle: String) throws {
        guard let document = PDFDocument(data: data) else {
            throw PDFExporterError.printFailed
        }
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: jobTitle
        ]

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.jobDisposition = .spool

        guard let operation = document.printOperation(
            for: printInfo,
            scalingMode: .pageScaleDownToFit,
            autoRotate: true
        ) else {
            throw PDFExporterError.printFailed
        }
        operation.jobTitle = jobTitle
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        // run() is modal and must run on main; we are already @MainActor.
        operation.run()
    }

    // MARK: - Rendering

    private static func renderPDF(
        settle: TimeInterval,
        timeout: TimeInterval,
        load: (WKWebView) -> Void
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            let config = WKWebViewConfiguration()
            config.suppressesIncrementalRendering = false
            config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

            let webView = WKWebView(
                frame: CGRect(x: 0, y: 0, width: pageWidth, height: minHeight),
                configuration: config
            )
            webView.setValue(false, forKey: "drawsBackground")

            // WKWebView createPDF is unreliable unless the view is in a window hierarchy.
            let window = NSWindow(
                contentRect: NSRect(x: -16_000, y: -16_000, width: pageWidth, height: minHeight),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.contentView = webView
            // Order without activating the app.
            window.orderBack(nil)

            let box = WebBox(
                webView: webView,
                window: window,
                continuation: cont,
                settle: settle,
                timeout: timeout
            )
            webView.navigationDelegate = box
            box.retainSelf = box
            load(webView)
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Navigation / PDF capture

    private final class WebBox: NSObject, WKNavigationDelegate {
        let webView: WKWebView
        let window: NSWindow
        var continuation: CheckedContinuation<Data, Error>?
        var retainSelf: WebBox?
        private var finished = false
        private let settle: TimeInterval
        private var timeoutItem: DispatchWorkItem?

        init(
            webView: WKWebView,
            window: NSWindow,
            continuation: CheckedContinuation<Data, Error>,
            settle: TimeInterval,
            timeout: TimeInterval
        ) {
            self.webView = webView
            self.window = window
            self.continuation = continuation
            self.settle = settle
            super.init()

            let item = DispatchWorkItem { [weak self] in
                self?.fail(PDFExporterError.timedOut)
            }
            timeoutItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: item)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Give layout / JS (canvas runtime) time to paint.
            DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
                self?.capturePDF()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        private func capturePDF() {
            guard !finished else { return }

            // Measure full document so long markdown/source isn't clipped to the viewport.
            webView.evaluateJavaScript(
                """
                (function() {
                  const body = document.body;
                  const doc = document.documentElement;
                  const w = Math.max(
                    body ? body.scrollWidth : 0,
                    doc ? doc.scrollWidth : 0,
                    \(Int(pageWidth))
                  );
                  const h = Math.max(
                    body ? body.scrollHeight : 0,
                    doc ? doc.scrollHeight : 0,
                    \(Int(minHeight))
                  );
                  return { w: w, h: h };
                })();
                """
            ) { [weak self] result, _ in
                guard let self, !self.finished else { return }

                var width = pageWidth
                var height = minHeight
                if let dict = result as? [String: Any] {
                    if let w = dict["w"] as? CGFloat { width = max(pageWidth, w) }
                    else if let w = dict["w"] as? Double { width = max(pageWidth, CGFloat(w)) }
                    else if let w = dict["w"] as? Int { width = max(pageWidth, CGFloat(w)) }
                    if let h = dict["h"] as? CGFloat { height = max(minHeight, h) }
                    else if let h = dict["h"] as? Double { height = max(minHeight, CGFloat(h)) }
                    else if let h = dict["h"] as? Int { height = max(minHeight, CGFloat(h)) }
                }
                // Cap extreme heights (pathological pages) to keep WebKit happy.
                height = min(height, 50_000)

                let frame = CGRect(x: 0, y: 0, width: width, height: height)
                self.webView.frame = frame
                self.window.setContentSize(NSSize(width: width, height: min(height, 4_000)))
                self.webView.layoutSubtreeIfNeeded()

                let config = WKPDFConfiguration()
                // Full document area — fixed viewport rect was clipping multi-page content.
                config.rect = CGRect(x: 0, y: 0, width: width, height: height)

                self.webView.createPDF(configuration: config) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let data):
                        if data.isEmpty {
                            self.fail(PDFExporterError.webViewFailed("PDF data was empty"))
                        } else {
                            self.finish(.success(data))
                        }
                    case .failure(let error):
                        self.fail(error)
                    }
                }
            }
        }

        private func fail(_ error: Error) {
            let wrapped: Error
            if error is PDFExporterError {
                wrapped = error
            } else {
                wrapped = PDFExporterError.webViewFailed(error.localizedDescription)
            }
            finish(.failure(wrapped))
        }

        private func finish(_ result: Result<Data, Error>) {
            guard !finished else { return }
            finished = true
            timeoutItem?.cancel()
            timeoutItem = nil
            continuation?.resume(with: result)
            continuation = nil
            webView.navigationDelegate = nil
            webView.stopLoading()
            window.orderOut(nil)
            window.contentView = nil
            retainSelf = nil
        }
    }
}
