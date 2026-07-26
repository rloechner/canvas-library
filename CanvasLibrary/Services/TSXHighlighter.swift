//
//  TSXHighlighter.swift
//  TSXPretty
//
//  Regex-driven syntax highlighter for TSX / JSX / TypeScript.
//  Uses resolved sRGB colors (not dynamic system colors) so NSTextView
//  always paints readable text in light and dark appearance.
//

import AppKit
import Foundation

struct TSXHighlighter {
    struct Theme {
        let plain: NSColor
        let comment: NSColor
        let string: NSColor
        let number: NSColor
        let keyword: NSColor
        let type: NSColor
        let function: NSColor
        let tag: NSColor
        let attribute: NSColor
        let punctuation: NSColor
        let background: NSColor

        static func current(appearance: NSAppearance? = nil) -> Theme {
            let app = appearance ?? NSApp.effectiveAppearance
            let isDark = app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? .dark : .light
        }

        static let light = Theme(
            plain: srgb(0.13, 0.13, 0.14),
            comment: srgb(0.45, 0.48, 0.52),
            string: srgb(0.12, 0.48, 0.22),
            number: srgb(0.55, 0.35, 0.05),
            keyword: srgb(0.55, 0.12, 0.62),
            type: srgb(0.08, 0.38, 0.58),
            function: srgb(0.10, 0.32, 0.72),
            tag: srgb(0.72, 0.12, 0.22),
            attribute: srgb(0.55, 0.40, 0.05),
            punctuation: srgb(0.40, 0.42, 0.45),
            background: srgb(0.99, 0.99, 0.98)
        )

        static let dark = Theme(
            plain: srgb(0.88, 0.89, 0.92),
            comment: srgb(0.48, 0.52, 0.58),
            string: srgb(0.55, 0.82, 0.55),
            number: srgb(0.86, 0.72, 0.45),
            keyword: srgb(0.82, 0.55, 0.90),
            type: srgb(0.48, 0.80, 0.92),
            function: srgb(0.45, 0.72, 0.98),
            tag: srgb(0.95, 0.55, 0.58),
            attribute: srgb(0.90, 0.78, 0.42),
            punctuation: srgb(0.62, 0.65, 0.70),
            background: srgb(0.12, 0.13, 0.16)
        )

        private static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
            NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
    }

    func highlight(_ source: String, fontSize: Double, theme: Theme = .current()) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping

        // Only set foreground colors — never background on runs. Background on
        // attributed runs caused invisible text in NSTextView over light panes.
        let output = NSMutableAttributedString(
            string: source,
            attributes: [
                .font: font,
                .foregroundColor: theme.plain,
                .paragraphStyle: paragraph,
            ]
        )

        let full = NSRange(location: 0, length: (source as NSString).length)
        guard full.length > 0 else { return output }

        var claimed = IndexSet()

        func apply(_ pattern: String, color: NSColor, font overrideFont: NSFont? = nil) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            regex.enumerateMatches(in: source, options: [], range: full) { match, _, _ in
                guard let match else { return }
                let range = match.range
                if range.location == NSNotFound || range.length == 0 { return }
                let idxs = IndexSet(integersIn: range.location..<(range.location + range.length))
                if !claimed.intersection(idxs).isEmpty { return }
                var attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: color,
                ]
                if let overrideFont { attrs[.font] = overrideFont }
                output.addAttributes(attrs, range: range)
                claimed.formUnion(idxs)
            }
        }

        apply(#"//[^\n]*"#, color: theme.comment)
        apply(#"/\*[\s\S]*?\*/"#, color: theme.comment)
        apply(#"`(?:\\.|[^`\\])*`"#, color: theme.string)
        apply(#""(?:\\.|[^"\\])*""#, color: theme.string)
        apply(#"'(?:\\.|[^'\\])*'"#, color: theme.string)

        apply(#"</?[A-Za-z_][\w.-]*|</?>|/>"#, color: theme.tag, font: bold)
        apply(#"(?<=\s)[A-Za-z_][\w:-]*(?=\s*=)"#, color: theme.attribute)

        let keywords = [
            "import", "export", "from", "as", "default", "type", "interface", "enum",
            "const", "let", "var", "function", "return", "if", "else", "for", "while",
            "do", "switch", "case", "break", "continue", "throw", "try", "catch",
            "finally", "new", "class", "extends", "implements", "super", "this",
            "typeof", "instanceof", "in", "of", "void", "null", "undefined", "true",
            "false", "async", "await", "yield", "static", "public", "private",
            "protected", "readonly", "abstract", "declare", "namespace", "module",
            "satisfies", "keyof", "infer", "is", "asserts", "with", "debugger",
        ].joined(separator: "|")
        apply(#"\b(?:\#(keywords))\b"#, color: theme.keyword, font: bold)
        apply(#"\b[A-Z][A-Za-z0-9_]*\b"#, color: theme.type)
        apply(#"\b[A-Za-z_][\w]*(?=\s*\()"#, color: theme.function)
        apply(#"\b(?:0x[0-9A-Fa-f]+|\d+\.?\d*(?:e[+-]?\d+)?)\b"#, color: theme.number)
        apply(#"[{}\[\]().,;:?]"#, color: theme.punctuation)

        return output
    }
}
