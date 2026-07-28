//
//  CanvasPreviewView.swift
//  Canvas Library
//
//  Canvas runtime host + optional design mode (unlock preview).
//

import SwiftUI
import WebKit

private let canvasScheme = "canvaslibrary-canvas"

struct CanvasPreviewView: NSViewRepresentable {
    let hostURL: URL?
    let workDirectory: URL?
    let reloadToken: UUID
    var isVisible: Bool = true
    var designMode: Bool = false
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?
    var onDesignTextEdit: ((String, String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onReady: onReady,
            onError: onError,
            onDesignTextEdit: onDesignTextEdit
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let handler = CanvasBundleSchemeHandler()
        context.coordinator.schemeHandler = handler
        config.setURLSchemeHandler(handler, forURLScheme: canvasScheme)

        let userContent = config.userContentController
        for name in ["canvasReady", "canvasError", "designEdit", "designMode"] {
            userContent.add(context.coordinator, name: name)
        }

        let consolePipe = """
        (function() {
          function send(level, args) {
            try {
              const msg = Array.from(args).map(a => {
                if (a instanceof Error) return a.stack || a.message;
                try { return typeof a === 'string' ? a : JSON.stringify(a); }
                catch { return String(a); }
              }).join(' ');
              if (level === 'error' || level === 'warn') {
                window.webkit?.messageHandlers?.canvasError?.postMessage('[' + level + '] ' + msg);
              }
            } catch (_) {}
          }
          const origErr = console.error;
          const origWarn = console.warn;
          console.error = function() { send('error', arguments); return origErr.apply(console, arguments); };
          console.warn = function() { send('warn', arguments); return origWarn.apply(console, arguments); };
          window.addEventListener('error', e => {
            window.webkit?.messageHandlers?.canvasError?.postMessage(
              (e.message || 'error') + (e.filename ? (' @ ' + e.filename + ':' + e.lineno) : '')
            );
          });
          window.addEventListener('unhandledrejection', e => {
            const r = e.reason;
            window.webkit?.messageHandlers?.canvasError?.postMessage(
              'unhandledrejection: ' + (r && r.stack ? r.stack : String(r))
            );
          });
        })();
        """
        userContent.addUserScript(WKUserScript(source: consolePipe, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.isHidden = !isVisible
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        context.coordinator.webView = webView
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        let uc = webView.configuration.userContentController
        for name in ["canvasReady", "canvasError", "designEdit", "designMode"] {
            uc.removeScriptMessageHandler(forName: name)
        }
        webView.navigationDelegate = nil
        coordinator.webView = nil
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onReady = onReady
        context.coordinator.onError = onError
        context.coordinator.onDesignTextEdit = onDesignTextEdit
        context.coordinator.schemeHandler?.rootDirectory = workDirectory
        context.coordinator.desiredDesignMode = designMode

        webView.isHidden = !isVisible
        webView.alphaValue = isVisible ? 1 : 0

        guard workDirectory != nil else {
            if isVisible {
                webView.loadHTMLString(
                    """
                    <html><body style="font-family:-apple-system;padding:24px;color:#888">
                    No canvas to preview.
                    </body></html>
                    """,
                    baseURL: nil
                )
            }
            return
        }

        if context.coordinator.loadedToken != reloadToken {
            context.coordinator.loadedToken = reloadToken
            // Capture scroll before tear-down so intentional reloads don't jump to top.
            context.coordinator.captureScrollThenLoad(
                webView,
                url: URL(string: "\(canvasScheme)://preview/host.html?t=\(reloadToken.uuidString)")!
            )
        } else if context.coordinator.appliedDesignMode != designMode {
            // Only toggle when the flag actually changes — re-applying every
            // SwiftUI update re-marks the DOM and feels like a rebuild.
            context.coordinator.applyDesignMode(designMode)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onReady: (() -> Void)?
        var onError: ((String) -> Void)?
        var onDesignTextEdit: ((String, String) -> Void)?
        var loadedToken: UUID?
        var schemeHandler: CanvasBundleSchemeHandler?
        var desiredDesignMode = false
        /// Last value sent to JS — avoid re-marking editables on every body refresh.
        var appliedDesignMode: Bool?
        weak var webView: WKWebView?
        private var reportedFatal = false
        /// Scroll to restore after the next full host load (x, y).
        private var pendingScroll: (x: Double, y: Double)?

        init(
            onReady: (() -> Void)?,
            onError: ((String) -> Void)?,
            onDesignTextEdit: ((String, String) -> Void)?
        ) {
            self.onReady = onReady
            self.onError = onError
            self.onDesignTextEdit = onDesignTextEdit
        }

        func captureScrollThenLoad(_ webView: WKWebView, url: URL) {
            webView.evaluateJavaScript("[window.scrollX||0, window.scrollY||0]") { [weak self] result, _ in
                guard let self else { return }
                if let pair = result as? [Any], pair.count == 2 {
                    let x = (pair[0] as? NSNumber)?.doubleValue
                        ?? (pair[0] as? Double)
                        ?? 0
                    let y = (pair[1] as? NSNumber)?.doubleValue
                        ?? (pair[1] as? Double)
                        ?? 0
                    // Only restore if we had scrolled away from the top.
                    if y > 8 || x > 8 {
                        self.pendingScroll = (x, y)
                    } else {
                        self.pendingScroll = nil
                    }
                } else {
                    self.pendingScroll = nil
                }
                webView.load(URLRequest(url: url))
            }
        }

        func restorePendingScrollIfNeeded() {
            guard let scroll = pendingScroll else { return }
            pendingScroll = nil
            let js = "window.scrollTo(\(scroll.x), \(scroll.y));"
            // Double-rAF: layout may not be final on the first canvasReady tick.
            let wrapped = """
            (function(){
              var x = \(scroll.x), y = \(scroll.y);
              function go(){ window.scrollTo(x, y); }
              go();
              if (window.requestAnimationFrame) {
                requestAnimationFrame(function(){ requestAnimationFrame(go); });
              } else {
                setTimeout(go, 50);
              }
            })();
            """
            webView?.evaluateJavaScript(wrapped, completionHandler: nil)
            _ = js
        }

        func applyDesignMode(_ on: Bool) {
            appliedDesignMode = on
            desiredDesignMode = on
            let flag = on ? "true" : "false"
            let js = """
            window.__csWantDesignMode = \(flag);
            if (window.CanvasLibraryDesign) {
              window.CanvasLibraryDesign.setEnabled(\(flag));
            }
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "canvasReady":
                reportedFatal = false
                DispatchQueue.main.async {
                    self.onReady?()
                    // After a full load, appliedDesignMode is stale relative to the new document.
                    self.appliedDesignMode = nil
                    self.applyDesignMode(self.desiredDesignMode)
                    self.restorePendingScrollIfNeeded()
                }
            case "canvasError":
                let text = (message.body as? String) ?? String(describing: message.body)
                let lower = text.lowercased()
                // Console pipe tags noise as [error]/[warn] — never treat as fatal overlay.
                if lower.hasPrefix("[error]") || lower.hasPrefix("[warn]") { return }
                // Real host/runtime failures: unhandled rejections, window errors, load failures.
                let isFatal = lower.contains("unhandledrejection")
                    || lower.contains("syntaxerror")
                    || lower.contains("not defined")
                    || lower.contains("failed to")
                    || lower.contains("could not")
                    || lower.contains("cannot find")
                if isFatal {
                    reportedFatal = true
                    DispatchQueue.main.async { self.onError?(text) }
                }
            case "designEdit":
                guard let body = message.body as? [String: Any],
                      let oldText = body["oldText"] as? String,
                      let newText = body["newText"] as? String
                else { return }
                DispatchQueue.main.async {
                    self.onDesignTextEdit?(oldText, newText)
                }
            case "designMode":
                break
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.onError?(error.localizedDescription) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.onError?(error.localizedDescription) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

// MARK: - Custom scheme static file server

final class CanvasBundleSchemeHandler: NSObject, WKURLSchemeHandler {
    var rootDirectory: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(SchemeError.badURL)
            return
        }

        guard let root = rootDirectory else {
            urlSchemeTask.didFailWithError(SchemeError.noRoot)
            return
        }

        var relative = requestURL.path
        if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
        if relative.isEmpty { relative = "host.html" }

        let fileURL = root.appendingPathComponent(relative).standardizedFileURL
        guard fileURL.path.hasPrefix(root.standardizedFileURL.path) else {
            urlSchemeTask.didFailWithError(SchemeError.forbidden)
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let mime = mimeType(for: fileURL.pathExtension)
            let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": mime,
                    "Content-Length": "\(data.count)",
                    "Access-Control-Allow-Origin": "*",
                    "Cache-Control": "no-store",
                ]
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "map": return "application/json"
        default: return "application/octet-stream"
        }
    }

    enum SchemeError: LocalizedError {
        case badURL, noRoot, forbidden
        var errorDescription: String? {
            switch self {
            case .badURL: return "Invalid canvas URL"
            case .noRoot: return "Canvas bundle directory not set"
            case .forbidden: return "Forbidden canvas path"
            }
        }
    }
}
