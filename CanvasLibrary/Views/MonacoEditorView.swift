//
//  MonacoEditorView.swift
//  Canvas Library
//
//  VS Code Monaco editor hosted in WKWebView — best-in-class TSX color coding.
//

import SwiftUI
import WebKit

struct MonacoEditorView: NSViewRepresentable {
    let text: String
    let language: String
    let fontSize: Double
    let showLineNumbers: Bool
    let isDark: Bool
    let isEditable: Bool
    let documentID: String
    /// When non-nil, reveal this 1-based line in the editor.
    var scrollToLine: Int? = nil
    var onTextChange: (String) -> Void
    var onSave: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange, onSave: onSave)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Allow local monaco AMD loader + modules
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        let uc = config.userContentController
        uc.add(context.coordinator, name: "editorReady")
        uc.add(context.coordinator, name: "editorChange")
        uc.add(context.coordinator, name: "editorSave")
        uc.add(context.coordinator, name: "editorError")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        context.coordinator.webView = webView

        if let hostDir = Self.editorHostDirectory(),
           let html = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "EditorHost")
            ?? hostDir.appendingPathComponent("editor.html") as URL?,
           FileManager.default.fileExists(atPath: html.path) {
            webView.loadFileURL(html, allowingReadAccessTo: hostDir)
            context.coordinator.hostLoaded = true
        } else if let hostDir = Self.editorHostDirectory() {
            let html = hostDir.appendingPathComponent("editor.html")
            webView.loadFileURL(html, allowingReadAccessTo: hostDir)
            context.coordinator.hostLoaded = true
        }

        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        let uc = webView.configuration.userContentController
        for name in ["editorReady", "editorChange", "editorSave", "editorError"] {
            uc.removeScriptMessageHandler(forName: name)
        }
        webView.navigationDelegate = nil
        coordinator.webView = nil
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onSave = onSave

        // Push document when ready / id changes / external format-save updates
        if context.coordinator.isReady {
            if context.coordinator.lastDocumentID != documentID {
                context.coordinator.lastDocumentID = documentID
                context.coordinator.pushValue(text, force: true)
                context.coordinator.pushLanguage(language)
            } else if !context.coordinator.isEcho,
                      context.coordinator.lastPushedText != text {
                // External update (format / revert)
                context.coordinator.pushValue(text, force: true)
            }

            if context.coordinator.lastDark != isDark {
                context.coordinator.lastDark = isDark
                context.coordinator.pushTheme(isDark)
            }
            if context.coordinator.lastFontSize != fontSize {
                context.coordinator.lastFontSize = fontSize
                context.coordinator.pushFontSize(fontSize)
            }
            if context.coordinator.lastLineNumbers != showLineNumbers {
                context.coordinator.lastLineNumbers = showLineNumbers
                context.coordinator.pushLineNumbers(showLineNumbers)
            }
            context.coordinator.pushReadOnly(!isEditable)
            if let line = scrollToLine, line > 0, context.coordinator.lastScrolledLine != line {
                context.coordinator.lastScrolledLine = line
                context.coordinator.revealLine(line)
            }
        } else {
            // Stash for when ready fires
            context.coordinator.pendingText = text
            context.coordinator.pendingLanguage = language
            context.coordinator.pendingDark = isDark
            context.coordinator.pendingFontSize = fontSize
            context.coordinator.pendingLineNumbers = showLineNumbers
            context.coordinator.pendingEditable = isEditable
            context.coordinator.pendingDocumentID = documentID
            context.coordinator.pendingScrollToLine = scrollToLine
        }
    }

    static func editorHostDirectory() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("EditorHost"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("editor.html").path) {
            return bundled
        }
        // Source-tree fallback
        let src = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/EditorHost")
        if FileManager.default.fileExists(atPath: src.appendingPathComponent("editor.html").path) {
            return src
        }
        return nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onTextChange: (String) -> Void
        var onSave: (() -> Void)?
        weak var webView: WKWebView?

        var isReady = false
        var hostLoaded = false
        var isEcho = false
        var lastPushedText: String?
        var lastDocumentID: String?
        var lastDark: Bool?
        var lastFontSize: Double?
        var lastLineNumbers: Bool?
        var lastScrolledLine: Int?

        var pendingText: String?
        var pendingLanguage: String?
        var pendingDark: Bool?
        var pendingFontSize: Double?
        var pendingLineNumbers: Bool?
        var pendingEditable: Bool?
        var pendingDocumentID: String?
        var pendingScrollToLine: Int?

        init(onTextChange: @escaping (String) -> Void, onSave: (() -> Void)?) {
            self.onTextChange = onTextChange
            self.onSave = onSave
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "editorReady":
                isReady = true
                if let id = pendingDocumentID { lastDocumentID = id }
                if let t = pendingText { pushValue(t, force: true) }
                if let lang = pendingLanguage { pushLanguage(lang) }
                if let dark = pendingDark {
                    lastDark = dark
                    pushTheme(dark)
                }
                if let size = pendingFontSize {
                    lastFontSize = size
                    pushFontSize(size)
                }
                if let nums = pendingLineNumbers {
                    lastLineNumbers = nums
                    pushLineNumbers(nums)
                }
                if let ed = pendingEditable { pushReadOnly(!ed) }
                if let line = pendingScrollToLine, line > 0 {
                    lastScrolledLine = line
                    revealLine(line)
                }
                DispatchQueue.main.async { self.eval("window.CanvasLibraryEditor && window.CanvasLibraryEditor.focus()") }
            case "editorChange":
                guard let text = message.body as? String else { return }
                isEcho = true
                lastPushedText = text
                onTextChange(text)
                DispatchQueue.main.async { self.isEcho = false }
            case "editorSave":
                DispatchQueue.main.async { self.onSave?() }
            case "editorError":
                let msg = (message.body as? String) ?? String(describing: message.body)
                NSLog("[MonacoEditor] %@", msg)
            default:
                break
            }
        }

        func pushValue(_ text: String, force: Bool) {
            lastPushedText = text
            let payload = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            // Use JSON encoding for safety
            guard let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed]),
                  let json = String(data: data, encoding: .utf8) else { return }
            eval("window.CanvasLibraryEditor && window.CanvasLibraryEditor.setValue(\(json))")
            _ = payload
            _ = force
        }

        func pushTheme(_ dark: Bool) {
            eval("window.CanvasLibraryEditor && window.CanvasLibraryEditor.setTheme(\(dark ? "true" : "false"))")
        }

        func pushFontSize(_ size: Double) {
            eval("window.CanvasLibraryEditor && window.CanvasLibraryEditor.setFontSize(\(size))")
        }

        func pushLineNumbers(_ on: Bool) {
            eval("window.CanvasLibraryEditor && window.CanvasLibraryEditor.setLineNumbers(\(on ? "true" : "false"))")
        }

        func pushLanguage(_ lang: String) {
            guard let data = try? JSONSerialization.data(withJSONObject: lang, options: [.fragmentsAllowed]),
                  let json = String(data: data, encoding: .utf8) else { return }
            eval("window.CanvasLibraryEditor && window.CanvasLibraryEditor.setLanguage(\(json))")
        }

        func pushReadOnly(_ ro: Bool) {
            eval("window.CanvasLibraryEditor && window.CanvasLibraryEditor.setReadOnly(\(ro ? "true" : "false"))")
        }

        func revealLine(_ line: Int) {
            eval("window.CanvasLibraryEditor && window.CanvasLibraryEditor.revealLine(\(line))")
        }

        func eval(_ js: String) {
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
