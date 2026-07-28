//
//  CanvasEnvironment.swift
//  Canvas Library
//
//  Detect Node / esbuild / canvas runtime readiness for status UX.
//

import Foundation

enum CanvasRuntimeSource: String, Equatable {
    case appBundle
    case sourceTree
    case cursorApp
    case minimalFallback
    case missing

    var displayName: String {
        switch self {
        case .appBundle: return "app bundle"
        case .sourceTree: return "source tree"
        case .cursorApp: return "Cursor.app"
        case .minimalFallback: return "minimal open host"
        case .missing: return "not found"
        }
    }
}

struct CanvasEnvironmentStatus: Equatable {
    var hasNode: Bool
    var nodePath: String?
    var hasRuntime: Bool
    var runtimeSource: CanvasRuntimeSource
    /// True when preview uses the limited open fallback (not full Cursor components).
    var isLimitedRuntime: Bool

    var isReadyForCanvasPreview: Bool {
        hasNode && hasRuntime
    }

    var shortSummary: String {
        if !hasNode && !hasRuntime {
            return "Canvas preview needs Node.js and a canvas runtime"
        }
        if !hasNode {
            return "Canvas preview needs Node.js (npx) on PATH"
        }
        if !hasRuntime {
            return "Canvas runtime not found — install Cursor or use minimal host"
        }
        if isLimitedRuntime {
            return "Preview runtime: \(runtimeSource.displayName) (limited components)"
        }
        return "Preview runtime: \(runtimeSource.displayName)"
    }

    var helpDetail: String {
        var lines: [String] = []
        if hasNode {
            lines.append("Node: \(nodePath ?? "available")")
        } else {
            lines.append("Node: missing — install from https://nodejs.org and ensure npx is on PATH")
        }
        lines.append("Runtime: \(runtimeSource.displayName)")
        if isLimitedRuntime {
            lines.append("Using the open minimal host — Cursor-specific components may be stubbed.")
        } else if !hasRuntime {
            lines.append("Install Cursor, or place canvas-runtime.esm.js under Resources/CanvasHost for dev.")
        }
        return lines.joined(separator: "\n")
    }
}

enum CanvasEnvironment {
    /// Probe Node + runtime locations. Safe to call off the main actor.
    static func probe() -> CanvasEnvironmentStatus {
        let node = resolveNodePath()
        let runtime = CanvasCompiler.resolveRuntimePresence()
        return CanvasEnvironmentStatus(
            hasNode: node != nil,
            nodePath: node,
            hasRuntime: runtime.source != .missing,
            runtimeSource: runtime.source,
            isLimitedRuntime: runtime.source == .minimalFallback
        )
    }

    static func resolveNodePath() -> String? {
        let fm = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to `which node` via zsh login path.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v node"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty, fm.isExecutableFile(atPath: path) else { return nil }
        return path
    }
}
