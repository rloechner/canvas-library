//
//  GitService.swift
//  Canvas Library
//
//  Thin shell-out to system `git` for the open document only.
//

import Foundation

enum GitFileStatus: Equatable, Sendable {
    case unknown
    case clean
    case untracked
    /// Index / worktree XY codes from porcelain (e.g. " M", "M ", "MM", "A ", "D ").
    case changed(index: Character, workTree: Character)

    var isInRepo: Bool {
        if case .unknown = self { return false }
        return true
    }

    var isClean: Bool {
        if case .clean = self { return true }
        return false
    }

    var isUntracked: Bool {
        if case .untracked = self { return true }
        return false
    }

    /// Any non-clean, known status (modified / staged / untracked).
    var isChanged: Bool {
        switch self {
        case .untracked, .changed:
            return true
        case .unknown, .clean:
            return false
        }
    }

    /// True when index has something staged for this path.
    var isStaged: Bool {
        switch self {
        case .changed(let i, _) where i != " " && i != "?":
            return true
        default:
            return false
        }
    }

    /// True when work tree differs from index (or untracked).
    var hasWorkTreeChanges: Bool {
        switch self {
        case .untracked:
            return true
        case .changed(_, let w) where w != " " && w != "?":
            return true
        default:
            return false
        }
    }

    /// Tracked file with uncommitted changes (staged and/or worktree) — discardable via `git restore`.
    var canDiscardToHEAD: Bool {
        switch self {
        case .changed:
            return true
        case .untracked, .unknown, .clean:
            return false
        }
    }

    /// Short label for the document-header capsule (nil = hide capsule).
    var capsuleTitle: String? {
        switch self {
        case .unknown, .clean:
            return nil
        case .untracked:
            return "Untracked"
        case .changed(let i, let w):
            let staged = i != " " && i != "?"
            let dirty = w != " " && w != "?"
            if staged && dirty { return "Staged+Modified" }
            if staged {
                switch i {
                case "A": return "Staged"
                case "D": return "Staged delete"
                case "R": return "Renamed"
                default: return "Staged"
                }
            }
            if dirty {
                switch w {
                case "D": return "Deleted"
                default: return "Modified"
                }
            }
            return "Changed"
        }
    }

    /// One-letter badge for the library sidebar (VS Code–style).
    var sidebarBadge: String? {
        switch self {
        case .unknown, .clean:
            return nil
        case .untracked:
            return "U"
        case .changed(let i, let w):
            let staged = i != " " && i != "?"
            let dirty = w != " " && w != "?"
            if staged && dirty { return "M" }
            if staged {
                switch i {
                case "A": return "A"
                case "D": return "D"
                case "R": return "R"
                case "M": return "M"
                default: return "S"
                }
            }
            if dirty {
                switch w {
                case "D": return "D"
                case "M": return "M"
                default: return "M"
                }
            }
            return "M"
        }
    }

    /// Accessibility / tooltip for the sidebar badge.
    var sidebarHelp: String? {
        capsuleTitle.map { "Git: \($0)" }
    }
}

enum GitServiceError: LocalizedError {
    case gitNotFound
    case failed(exitCode: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "git not found (install Xcode CLT or Homebrew git)"
        case .failed(_, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "git command failed" : trimmed
        }
    }
}

struct GitService: Sendable {
    /// Resolve absolute path to `git` binary.
    private func gitExecutable() -> String? {
        let candidates = [
            "/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Xcode CLT shim path
        let xcodeGit = "/Applications/Xcode.app/Contents/Developer/usr/libexec/git-core/git"
        if FileManager.default.isExecutableFile(atPath: xcodeGit) {
            return xcodeGit
        }
        return nil
    }

    // MARK: - Public API

    func findGitRoot(startingAt fileURL: URL) -> URL? {
        let startDir = fileURL.hasDirectoryPath ? fileURL : fileURL.deletingLastPathComponent()
        // 1) Walk up from the file (normal case: docs live inside the repo).
        if let root = revParseTopLevel(cwd: startDir) {
            return root
        }
        // 2) Cursor stores canvases under ~/.cursor/projects/<encoded-path>/canvases/.
        //    The real git root is usually the decoded workspace, not .cursor.
        for candidate in cursorWorkspaceCandidates(for: fileURL) {
            if let root = revParseTopLevel(cwd: candidate) {
                return root
            }
            // Workspace itself might be the root even if rev-parse needs that cwd.
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir),
               isDir.boolValue,
               FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".git").path),
               let root = revParseTopLevel(cwd: candidate) {
                return root
            }
        }
        return nil
    }

    /// Map open file path → candidate real project directories for git.
    private func cursorWorkspaceCandidates(for fileURL: URL) -> [URL] {
        let path = fileURL.standardizedFileURL.path
        let marker = "/.cursor/projects/"
        guard let range = path.range(of: marker) else { return [] }
        let after = path[range.upperBound...]
        let projectSegment = after.split(separator: "/").first.map(String.init) ?? ""
        guard !projectSegment.isEmpty else { return [] }

        var urls: [URL] = []
        if let decoded = Self.decodeCursorProjectFolder(projectSegment) {
            urls.append(URL(fileURLWithPath: decoded))
        }
        // Also try /Users/... literal rebuild
        if projectSegment.hasPrefix("Users-") {
            let slashPath = "/" + projectSegment.split(separator: "-").joined(separator: "/")
            // That loses multi-segment names; prefer decodeCursorProjectFolder.
            _ = slashPath
        }
        return urls
    }

    /// Decode Cursor project dir names (encoded by replacing `/` with `-`).
    /// `Users-ryan-srv-shortyawards` → `/Users/ryan/srv/shortyawards`
    /// Uses greedy existence checks so hyphenated folder names still resolve.
    static func decodeCursorProjectFolder(_ raw: String) -> String? {
        if raw.allSatisfy(\.isNumber) { return nil }
        if raw.hasPrefix("var-folders") || raw == "empty-window" { return nil }

        let segments = raw.split(separator: "-").map(String.init)
        guard segments.count >= 2 else { return nil }

        // Build absolute path by consuming segments, preferring existing directories.
        // Start: first segment is often "Users" → "/Users"
        var path = "/" + segments[0]
        var i = 1
        let fm = FileManager.default
        while i < segments.count {
            // Prefer longest existing suffix match for ambiguous hyphenated names.
            var matched: String?
            for len in stride(from: segments.count - i, through: 1, by: -1) {
                let piece = segments[i..<(i + len)].joined(separator: "-")
                let candidate = path + "/" + piece
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                    matched = candidate
                    i += len
                    break
                }
            }
            if let matched {
                path = matched
            } else {
                // Fall back: treat next segment as a path component (joined with - if needed)
                path = path + "/" + segments[i]
                i += 1
            }
        }
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return path
        }
        // Fallback anchors for common layouts even if mid-path missing
        if raw.hasPrefix("Users-"), let range = raw.range(of: "-srv-") {
            let afterUsers = raw[raw.index(raw.startIndex, offsetBy: 6)...]
            let userEnd = afterUsers.range(of: "-srv-")!.lowerBound
            let user = String(afterUsers[..<userEnd])
            let project = String(raw[range.upperBound...])
            return "/Users/\(user)/srv/\(project)"
        }
        return nil
    }

    private func revParseTopLevel(cwd: URL) -> URL? {
        guard let out = try? run(arguments: ["rev-parse", "--show-toplevel"], cwd: cwd),
              out.exitCode == 0
        else { return nil }
        let path = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    func currentBranch(repoRoot: URL) -> String? {
        guard let out = try? run(arguments: ["rev-parse", "--abbrev-ref", "HEAD"], cwd: repoRoot),
              out.exitCode == 0
        else { return nil }
        let b = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? nil : b
    }

    func relativePath(fileURL: URL, repoRoot: URL) -> String? {
        let file = fileURL.standardizedFileURL.path
        let root = repoRoot.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard file.hasPrefix(prefix) else {
            if file == root { return "" }
            return nil
        }
        return String(file.dropFirst(prefix.count))
    }

    func fileStatus(repoRoot: URL, pathRelativeToRoot: String) -> GitFileStatus {
        guard let out = try? run(
            arguments: [
                "status", "--porcelain=v1", "--untracked-files=all", "--", pathRelativeToRoot,
            ],
            cwd: repoRoot
        ), out.exitCode == 0
        else { return .unknown }

        let line = out.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .first?
            .trimmingCharacters(in: .newlines)

        guard let line, line.count >= 2 else { return .clean }
        return Self.parsePorcelainLine(line)?.status ?? .clean
    }

    /// Full-repo porcelain map: relative path → status (only non-clean entries).
    func statusMap(repoRoot: URL) -> [String: GitFileStatus] {
        guard let out = try? run(
            arguments: ["status", "--porcelain=v1", "--untracked-files=all"],
            cwd: repoRoot
        ), out.exitCode == 0
        else { return [:] }

        var map: [String: GitFileStatus] = [:]
        for raw in out.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            guard let parsed = Self.parsePorcelainLine(line) else { continue }
            map[parsed.path] = parsed.status
            // Renames: also mark the old path if present.
            if let old = parsed.oldPath {
                map[old] = parsed.status
            }
        }
        return map
    }

    /// Parse one `git status --porcelain=v1` line.
    private static func parsePorcelainLine(_ line: String) -> (path: String, oldPath: String?, status: GitFileStatus)? {
        guard line.count >= 3 else { return nil }
        if line.hasPrefix("??") {
            let path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { return nil }
            return (unquotePorcelainPath(path), nil, .untracked)
        }
        // XY path  or  XY old -> new
        let index = line[line.startIndex]
        let work = line[line.index(after: line.startIndex)]
        let rest = String(line.dropFirst(3))
        let status = GitFileStatus.changed(index: index, workTree: work)
        if let arrow = rest.range(of: " -> ") {
            let oldPath = unquotePorcelainPath(String(rest[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces))
            let newPath = unquotePorcelainPath(String(rest[arrow.upperBound...]).trimmingCharacters(in: .whitespaces))
            guard !newPath.isEmpty else { return nil }
            return (newPath, oldPath.isEmpty ? nil : oldPath, status)
        }
        let path = unquotePorcelainPath(rest.trimmingCharacters(in: .whitespaces))
        guard !path.isEmpty else { return nil }
        return (path, nil, status)
    }

    private static func unquotePorcelainPath(_ path: String) -> String {
        var p = path
        if p.hasPrefix("\"") && p.hasSuffix("\"") && p.count >= 2 {
            p = String(p.dropFirst().dropLast())
            p = p.replacingOccurrences(of: "\\\"", with: "\"")
            p = p.replacingOccurrences(of: "\\\\", with: "\\")
        }
        return p
    }

    func diff(repoRoot: URL, pathRelativeToRoot: String, staged: Bool) throws -> String {
        var args = ["diff"]
        if staged { args.append("--cached") }
        args.append(contentsOf: ["--", pathRelativeToRoot])
        let out = try run(arguments: args, cwd: repoRoot)
        if out.exitCode != 0 {
            throw GitServiceError.failed(exitCode: out.exitCode, message: out.stderr)
        }
        return out.stdout
    }

    func stage(repoRoot: URL, pathRelativeToRoot: String) throws {
        let out = try run(arguments: ["add", "--", pathRelativeToRoot], cwd: repoRoot)
        if out.exitCode != 0 {
            throw GitServiceError.failed(exitCode: out.exitCode, message: out.stderr)
        }
    }

    func unstage(repoRoot: URL, pathRelativeToRoot: String) throws {
        // restore --staged is modern; falls back if needed
        var out = try run(arguments: ["restore", "--staged", "--", pathRelativeToRoot], cwd: repoRoot)
        if out.exitCode != 0 {
            out = try run(arguments: ["reset", "HEAD", "--", pathRelativeToRoot], cwd: repoRoot)
        }
        if out.exitCode != 0 {
            throw GitServiceError.failed(exitCode: out.exitCode, message: out.stderr)
        }
    }

    /// Reset a tracked file to HEAD (index + worktree). Does not delete untracked files.
    func discardToHEAD(repoRoot: URL, pathRelativeToRoot: String) throws {
        var out = try run(
            arguments: ["restore", "--source=HEAD", "--staged", "--worktree", "--", pathRelativeToRoot],
            cwd: repoRoot
        )
        if out.exitCode != 0 {
            out = try run(arguments: ["checkout", "HEAD", "--", pathRelativeToRoot], cwd: repoRoot)
        }
        if out.exitCode != 0 {
            throw GitServiceError.failed(exitCode: out.exitCode, message: out.stderr)
        }
    }

    func commit(repoRoot: URL, message: String) throws {
        let out = try run(arguments: ["commit", "-m", message], cwd: repoRoot)
        if out.exitCode != 0 {
            throw GitServiceError.failed(exitCode: out.exitCode, message: out.stderr)
        }
    }

    // MARK: - Process

    private struct RunResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func run(arguments: [String], cwd: URL) throws -> RunResult {
        guard let exe = gitExecutable() else {
            throw GitServiceError.gitNotFound
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.environment = ProcessInfo.processInfo.environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return RunResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
