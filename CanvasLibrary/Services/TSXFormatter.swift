//
//  TSXFormatter.swift
//  TSXPretty
//
//  Prefers Prettier (npx) when Node is available; falls back to a
//  simple brace/tag-aware indent formatter.
//

import Foundation

struct FormatResult {
    let output: String
    let engineDescription: String
}

struct TSXFormatter {
    func format(_ source: String) -> FormatResult {
        if let pretty = runPrettier(source) {
            return FormatResult(output: pretty, engineDescription: "Formatted with Prettier")
        }
        let fallback = indentFormat(source)
        return FormatResult(output: fallback, engineDescription: "Formatted with built-in indent")
    }

    // MARK: - Prettier

    private func runPrettier(_ source: String) -> String? {
        let tempDir = FileManager.default.temporaryDirectory
        let inputURL = tempDir.appendingPathComponent("tsxpretty-\(UUID().uuidString).tsx")
        defer { try? FileManager.default.removeItem(at: inputURL) }

        do {
            try source.write(to: inputURL, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }

        // Prefer npx prettier; also try a global prettier binary.
        let candidates: [(String, [String])] = [
            ("/opt/homebrew/bin/npx", ["--yes", "prettier@3", "--parser", "typescript", inputURL.path]),
            ("/usr/local/bin/npx", ["--yes", "prettier@3", "--parser", "typescript", inputURL.path]),
            ("/opt/homebrew/bin/prettier", ["--parser", "typescript", inputURL.path]),
            ("/usr/local/bin/prettier", ["--parser", "typescript", inputURL.path]),
        ]

        for (launchPath, args) in candidates {
            guard FileManager.default.isExecutableFile(atPath: launchPath) else { continue }
            if let output = runProcess(launchPath: launchPath, arguments: args) {
                return output
            }
        }

        // PATH lookup via /bin/zsh
        if let output = runProcess(
            launchPath: "/bin/zsh",
            arguments: ["-lc", "npx --yes prettier@3 --parser typescript \(shellEscape(inputURL.path))"]
        ) {
            return output
        }

        return nil
    }

    private func runProcess(launchPath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Built-in indent formatter

    /// Conservative pretty-printer: normalizes indentation for braces,
    /// parentheses, and JSX-ish tags without rewriting AST.
    func indentFormat(_ source: String) -> String {
        let indentUnit = "  "
        var depth = 0
        var result: [String] = []
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                result.append("")
                continue
            }

            // Decrease depth for leading closers before printing
            let leadingClosers = countLeadingClosers(trimmed)
            let printDepth = max(0, depth - leadingClosers)

            result.append(String(repeating: indentUnit, count: printDepth) + trimmed)

            depth = max(0, depth + netDepthChange(trimmed))
        }

        // Collapse more than 2 consecutive blank lines
        var cleaned: [String] = []
        var blankRun = 0
        for line in result {
            if line.isEmpty {
                blankRun += 1
                if blankRun <= 2 { cleaned.append(line) }
            } else {
                blankRun = 0
                cleaned.append(line)
            }
        }

        var text = cleaned.joined(separator: "\n")
        if !text.hasSuffix("\n") { text += "\n" }
        return text
    }

    private func countLeadingClosers(_ line: String) -> Int {
        var count = 0
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if ch == "}" || ch == "]" || ch == ")" {
                count += 1
                i = line.index(after: i)
            } else if line[i...].hasPrefix("</") {
                count += 1
                // skip to end of tag name-ish
                break
            } else if ch == "/" && line.index(after: i) < line.endIndex {
                break
            } else {
                break
            }
        }
        // Also: line that is only `/>` or `>`
        if line.hasPrefix("/>") || line == ">" { return max(count, 1) }
        if line.hasPrefix("</") { return max(count, 1) }
        return count
    }

    private func netDepthChange(_ line: String) -> Int {
        // Strip strings/comments roughly for depth counting
        let scrubbed = scrub(line)
        var delta = 0
        var i = scrubbed.startIndex
        while i < scrubbed.endIndex {
            let ch = scrubbed[i]
            if ch == "{" || ch == "[" || ch == "(" {
                delta += 1
            } else if ch == "}" || ch == "]" || ch == ")" {
                delta -= 1
            } else if ch == "<" {
                let rest = scrubbed[i...]
                if rest.hasPrefix("</") {
                    delta -= 1
                    i = scrubbed.index(i, offsetBy: 2, limitedBy: scrubbed.endIndex) ?? scrubbed.endIndex
                    continue
                } else if rest.hasPrefix("<>") {
                    delta += 1
                    i = scrubbed.index(i, offsetBy: 2, limitedBy: scrubbed.endIndex) ?? scrubbed.endIndex
                    continue
                } else if isOpenTag(rest) {
                    // self-closing?
                    if let close = rest.firstIndex(of: ">") {
                        let tag = rest[...close]
                        if !tag.contains("/>") {
                            delta += 1
                        }
                        i = scrubbed.index(after: close)
                        continue
                    }
                }
            }
            i = scrubbed.index(after: i)
        }
        return delta
    }

    private func isOpenTag(_ rest: Substring) -> Bool {
        guard rest.hasPrefix("<") else { return false }
        guard rest.count > 1 else { return false }
        let second = rest[rest.index(after: rest.startIndex)]
        return second.isLetter || second == "_" || second == ">"
    }

    private func scrub(_ line: String) -> String {
        var out = ""
        var i = line.startIndex
        while i < line.endIndex {
            if line[i...].hasPrefix("//") { break }
            let ch = line[i]
            if ch == "\"" || ch == "'" || ch == "`" {
                let q = ch
                out.append(" ")
                i = line.index(after: i)
                while i < line.endIndex {
                    if line[i] == "\\" {
                        i = line.index(after: i)
                        if i < line.endIndex { i = line.index(after: i) }
                        continue
                    }
                    if line[i] == q {
                        i = line.index(after: i)
                        break
                    }
                    i = line.index(after: i)
                }
                continue
            }
            out.append(ch)
            i = line.index(after: i)
        }
        return out
    }
}
