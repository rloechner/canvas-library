//
//  MarkdownRenderer.swift
//  Canvas Library
//
//  Lightweight markdown → HTML for WKWebView preview.
//

import Foundation

enum MarkdownRenderer {
    /// - Parameter forPrint: light paper styling + `@page` margins for PDF/print export.
    static func htmlDocument(from markdown: String, isDark: Bool, forPrint: Bool = false) -> String {
        let body = renderBody(markdown)
        // Print/PDF always uses a light paper theme for readability.
        let printMode = forPrint
        let dark = isDark && !printMode
        let bg = dark ? "#1e1e1e" : "#ffffff"
        let fg = dark ? "#e4e4e4" : "#1a1a1a"
        let muted = dark ? "#9a9a9a" : "#666666"
        let codeBg = dark ? "#2a2a2a" : "#f4f4f5"
        let border = dark ? "#333" : "#e5e5e5"
        let link = dark ? "#6cb6ff" : "#0969da"
        let pageCSS = printMode
            ? "@page { margin: 0.6in; size: letter; }\n          * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }"
            : ""
        let contentPad = printMode ? "0" : "28px 36px 48px"
        let contentMax = printMode ? "none" : "820px"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <style>
          \(pageCSS)
          :root { color-scheme: \(dark ? "dark" : "light"); }
          html, body {
            margin: 0; padding: 0;
            background: \(bg); color: \(fg);
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            font-size: \(printMode ? "11pt" : "14px"); line-height: 1.55;
          }
          .content { padding: \(contentPad); max-width: \(contentMax); }
          h1 { font-size: 1.75rem; font-weight: 650; margin: 0 0 0.6em; }
          h2 { font-size: 1.35rem; font-weight: 650; margin: 1.4em 0 0.5em; }
          h3 { font-size: 1.1rem; font-weight: 600; margin: 1.2em 0 0.4em; }
          p, ul, ol { margin: 0 0 0.9em; }
          ul, ol { padding-left: 1.4em; }
          a { color: \(link); }
          code {
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            font-size: 0.9em;
            background: \(codeBg);
            padding: 0.12em 0.35em;
            border-radius: 4px;
          }
          pre {
            background: \(codeBg);
            border: 1px solid \(border);
            border-radius: 8px;
            padding: 12px 14px;
            overflow-x: auto;
            margin: 0 0 1em;
          }
          pre code { background: none; padding: 0; }
          blockquote {
            margin: 0 0 1em; padding: 0.2em 0 0.2em 1em;
            border-left: 3px solid \(border); color: \(muted);
          }
          hr { border: none; border-top: 1px solid \(border); margin: 1.5em 0; }
          table { border-collapse: collapse; width: 100%; margin: 0 0 1em; }
          th, td { border: 1px solid \(border); padding: 8px 10px; text-align: left; }
          th { background: \(codeBg); }
        </style>
        </head>
        <body><div class="content">\(body)</div></body>
        </html>
        """
    }

    /// Minimal GFM-ish renderer (headings, lists, code, links, emphasis, tables-lite).
    private static func renderBody(_ md: String) -> String {
        let lines = md.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var html: [String] = []
        var i = 0
        var inCode = false
        var codeLang = ""
        var codeLines: [String] = []
        var inList = false
        var listOrdered = false

        func closeList() {
            if inList {
                html.append(listOrdered ? "</ol>" : "</ul>")
                inList = false
            }
        }

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                if inCode {
                    let code = codeLines.joined(separator: "\n")
                    html.append("<pre><code\(codeLang.isEmpty ? "" : " class=\"language-\(escapeAttr(codeLang))\"")>\(escapeHTML(code))</code></pre>")
                    codeLines = []
                    codeLang = ""
                    inCode = false
                } else {
                    closeList()
                    inCode = true
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                i += 1
                continue
            }

            if inCode {
                codeLines.append(line)
                i += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                closeList()
                i += 1
                continue
            }

            if line.hasPrefix("### ") {
                closeList()
                html.append("<h3>\(inline(String(line.dropFirst(4))))</h3>")
            } else if line.hasPrefix("## ") {
                closeList()
                html.append("<h2>\(inline(String(line.dropFirst(3))))</h2>")
            } else if line.hasPrefix("# ") {
                closeList()
                html.append("<h1>\(inline(String(line.dropFirst(2))))</h1>")
            } else if line.hasPrefix("> ") {
                closeList()
                html.append("<blockquote><p>\(inline(String(line.dropFirst(2))))</p></blockquote>")
            } else if line == "---" || line == "***" {
                closeList()
                html.append("<hr/>")
            } else if let m = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                if !inList || !listOrdered {
                    closeList()
                    html.append("<ol>")
                    inList = true
                    listOrdered = true
                }
                let item = String(line[m.upperBound...])
                html.append("<li>\(inline(item))</li>")
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !inList || listOrdered {
                    closeList()
                    html.append("<ul>")
                    inList = true
                    listOrdered = false
                }
                html.append("<li>\(inline(String(line.dropFirst(2))))</li>")
            } else {
                closeList()
                html.append("<p>\(inline(line))</p>")
            }
            i += 1
        }

        if inCode {
            html.append("<pre><code>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>")
        }
        closeList()
        return html.joined(separator: "\n")
    }

    private static func inline(_ text: String) -> String {
        var s = escapeHTML(text)
        // `code`
        s = replace(s, pattern: #"`([^`]+)`"#, template: "<code>$1</code>")
        // **bold**
        s = replace(s, pattern: #"\*\*([^*]+)\*\*"#, template: "<strong>$1</strong>")
        // *italic*
        s = replace(s, pattern: #"\*([^*]+)\*"#, template: "<em>$1</em>")
        // [text](url)
        s = replace(s, pattern: #"\[([^\]]+)\]\(([^)]+)\)"#, template: "<a href=\"$2\">$1</a>")
        return s
    }

    private static func replace(_ s: String, pattern: String, template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: template)
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func escapeAttr(_ s: String) -> String {
        escapeHTML(s).replacingOccurrences(of: "'", with: "&#39;")
    }
}
