//
//  TSXOutlineParser.swift
//  TSXPretty
//
//  Lightweight stack-based JSX tag scanner (not a full TS parser).
//

import Foundation

struct TSXOutlineParser {
    func parse(_ source: String) -> [OutlineNode] {
        let stripped = stripStringsAndComments(source)
        var builder = TreeBuilder()

        // Open/close/self-closing tags and fragments: <Tag>, </Tag>, <Tag/>, <>, </>
        let pattern = #"</?([A-Za-z_][\w.-]*)?(\s[^>]*)?/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let ns = stripped as NSString
        let full = NSRange(location: 0, length: ns.length)

        for match in regex.matches(in: stripped, range: full) {
            let tagText = ns.substring(with: match.range)
            let isClose = tagText.hasPrefix("</")
            let isSelfClosing = tagText.hasSuffix("/>")

            let name: String
            let nameRange = match.range(at: 1)
            if nameRange.location != NSNotFound, nameRange.length > 0 {
                name = ns.substring(with: nameRange)
            } else {
                name = "Fragment"
            }

            // Skip TypeScript generics: Foo<Bar>, Array<string>
            if !isClose && looksLikeGeneric(before: match.range.location, in: source) {
                continue
            }

            let banned: Set<String> = [
                "as", "extends", "infer", "keyof", "typeof", "readonly", "unique", "asserts",
            ]
            if banned.contains(name) { continue }

            let (line, column) = lineAndColumn(in: source, utf16Offset: match.range.location)

            if isClose {
                builder.close(name: name)
                continue
            }

            let kind: OutlineNode.Kind
            if name == "Fragment" {
                kind = .fragment
            } else if isSelfClosing {
                kind = .selfClosing
            } else if name.first?.isUppercase == true || name.contains(".") {
                kind = .component
            } else {
                kind = .element
            }

            builder.open(
                name: name,
                kind: kind,
                line: line,
                column: column,
                selfClosing: isSelfClosing
            )
        }

        return builder.roots()
    }

    // MARK: - Tree builder

    private final class TreeBuilder {
        private final class MutableNode {
            let id: String
            let name: String
            let kind: OutlineNode.Kind
            let line: Int
            let column: Int
            var children: [MutableNode] = []

            init(id: String, name: String, kind: OutlineNode.Kind, line: Int, column: Int) {
                self.id = id
                self.name = name
                self.kind = kind
                self.line = line
                self.column = column
            }

            func freeze() -> OutlineNode {
                OutlineNode(
                    id: id,
                    name: name,
                    kind: kind,
                    line: line,
                    column: column,
                    children: children.map { $0.freeze() }
                )
            }
        }

        private var rootNodes: [MutableNode] = []
        private var stack: [MutableNode] = []
        private var counter = 0

        func open(name: String, kind: OutlineNode.Kind, line: Int, column: Int, selfClosing: Bool) {
            counter += 1
            let node = MutableNode(
                id: "\(counter)-\(line)-\(name)",
                name: name,
                kind: kind,
                line: line,
                column: column
            )

            if let parent = stack.last {
                parent.children.append(node)
            } else {
                rootNodes.append(node)
            }

            if !selfClosing {
                stack.append(node)
            }
        }

        func close(name: String) {
            guard !stack.isEmpty else { return }
            // Pop until matching open tag (handles imperfect markup)
            if let idx = stack.lastIndex(where: { $0.name == name }) {
                stack.removeSubrange(idx...)
            } else {
                stack.removeLast()
            }
        }

        func roots() -> [OutlineNode] {
            rootNodes.map { $0.freeze() }
        }
    }

    // MARK: - Helpers

    private func looksLikeGeneric(before offset: Int, in source: String) -> Bool {
        guard offset > 0 else { return false }
        let ns = source as NSString
        var i = offset - 1
        while i >= 0 {
            let ch = ns.character(at: i)
            if ch == 32 || ch == 9 || ch == 10 || ch == 13 {
                i -= 1
                continue
            }
            let isIdent =
                (ch >= 65 && ch <= 90) ||
                (ch >= 97 && ch <= 122) ||
                (ch >= 48 && ch <= 57) ||
                ch == 95
            // Identifier, `>`, or `]` immediately before `<` → likely a generic
            if isIdent || ch == 62 || ch == 93 {
                return true
            }
            return false
        }
        return false
    }

    private func lineAndColumn(in source: String, utf16Offset: Int) -> (Int, Int) {
        let ns = source as NSString
        var line = 1
        var col = 1
        let limit = min(utf16Offset, ns.length)
        for i in 0..<limit {
            if ns.character(at: i) == 10 {
                line += 1
                col = 1
            } else {
                col += 1
            }
        }
        return (line, col)
    }

    /// Replace string/comment contents with spaces so tag regex won't match inside them.
    private func stripStringsAndComments(_ source: String) -> String {
        var out = Array(source)
        let chars = Array(source)
        var i = 0
        let n = chars.count

        func spaceOut(_ from: Int, _ to: Int) {
            for j in from..<min(to, n) where out[j] != "\n" {
                out[j] = " "
            }
        }

        while i < n {
            if i + 1 < n && chars[i] == "/" && chars[i + 1] == "/" {
                let start = i
                i += 2
                while i < n && chars[i] != "\n" { i += 1 }
                spaceOut(start, i)
                continue
            }
            if i + 1 < n && chars[i] == "/" && chars[i + 1] == "*" {
                let start = i
                i += 2
                while i + 1 < n && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(i + 2, n)
                spaceOut(start, i)
                continue
            }
            if chars[i] == "\"" || chars[i] == "'" || chars[i] == "`" {
                let quote = chars[i]
                let start = i
                i += 1
                while i < n {
                    if chars[i] == "\\" { i += 2; continue }
                    if chars[i] == quote { i += 1; break }
                    i += 1
                }
                spaceOut(start, i)
                continue
            }
            i += 1
        }
        return String(out)
    }
}
