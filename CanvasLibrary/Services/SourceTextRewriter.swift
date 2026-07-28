//
//  SourceTextRewriter.swift
//  Canvas Library
//
//  Maps in-preview text edits back into TSX/MD source.
//

import Foundation

struct SourceTextRewriteResult {
    let text: String
    let replaced: Bool
    let strategy: String
    let occurrenceCount: Int
}

enum SourceTextRewriter {
    /// Replace `oldText` as it appears in source with `newText`.
    static func replace(oldText: String, with newText: String, in source: String) -> SourceTextRewriteResult {
        let old = oldText
        let new = newText
        if old == new {
            return SourceTextRewriteResult(text: source, replaced: false, strategy: "unchanged", occurrenceCount: 0)
        }
        if old.isEmpty {
            return SourceTextRewriteResult(text: source, replaced: false, strategy: "empty-old", occurrenceCount: 0)
        }

        // 1) Double-quoted string literal
        if let r = replaceQuoted(old, new, in: source, quote: "\"") {
            return r
        }
        // 2) Single-quoted string literal
        if let r = replaceQuoted(old, new, in: source, quote: "'") {
            return r
        }
        // 3) Template literal simple (no ${})
        if !old.contains("${"), let r = replaceQuoted(old, new, in: source, quote: "`") {
            return r
        }
        // 4) JSX text content: >…old…<
        if let r = replaceJSXText(old, new, in: source) {
            return r
        }
        // 5) Raw first occurrence (last resort)
        let count = source.components(separatedBy: old).count - 1
        if count > 0, let range = source.range(of: old) {
            var s = source
            s.replaceSubrange(range, with: new)
            return SourceTextRewriteResult(text: s, replaced: true, strategy: "raw", occurrenceCount: count)
        }

        return SourceTextRewriteResult(text: source, replaced: false, strategy: "not-found", occurrenceCount: 0)
    }

    private static func replaceQuoted(
        _ old: String,
        _ new: String,
        in source: String,
        quote: Character
    ) -> SourceTextRewriteResult? {
        let q = String(quote)
        let oldLit = q + escapeForJSString(old, quote: quote) + q
        let newLit = q + escapeForJSString(new, quote: quote) + q
        let count = source.components(separatedBy: oldLit).count - 1
        guard count > 0, let range = source.range(of: oldLit) else { return nil }
        var s = source
        s.replaceSubrange(range, with: newLit)
        return SourceTextRewriteResult(
            text: s,
            replaced: true,
            strategy: "quoted-\(quote)",
            occurrenceCount: count
        )
    }

    private static func replaceJSXText(_ old: String, _ new: String, in source: String) -> SourceTextRewriteResult? {
        // Match >optionalWS old optionalWS<
        let pattern = ">(\\s*)" + NSRegularExpression.escapedPattern(for: old) + "(\\s*)<"
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = source as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = re.matches(in: source, options: [], range: full)
        guard let first = matches.first else { return nil }
        let replacement = ">\(ns.substring(with: first.range(at: 1)))\(new)\(ns.substring(with: first.range(at: 2)))<"
        let result = re.stringByReplacingMatches(
            in: source,
            options: [],
            range: first.range,
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
        // escapedTemplate may over-escape; do manual range replace instead
        guard let swiftRange = Range(first.range, in: source) else { return nil }
        var s = source
        let pre = String(source[swiftRange].dropFirst().prefix(while: { $0.isWhitespace || $0 == "\n" || $0 == "\r" }))
        // Simpler: rebuild from capture groups
        let g1 = ns.substring(with: first.range(at: 1))
        let g2 = ns.substring(with: first.range(at: 2))
        s.replaceSubrange(swiftRange, with: ">\(g1)\(new)\(g2)<")
        _ = result
        return SourceTextRewriteResult(
            text: s,
            replaced: true,
            strategy: "jsx-text",
            occurrenceCount: matches.count
        )
    }

    private static func escapeForJSString(_ s: String, quote: Character) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch == quote {
                    out.append("\\")
                    out.append(ch)
                } else {
                    out.append(ch)
                }
            }
        }
        return out
    }
}
