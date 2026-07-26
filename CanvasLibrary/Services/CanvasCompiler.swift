//
//  CanvasCompiler.swift
//  Canvas Library
//
//  Transpiles .canvas.tsx via esbuild for the Cursor canvas runtime.
//

import Foundation

struct CanvasCompileResult {
    let workDirectory: URL
    let hostURL: URL
}

enum CanvasCompilerError: LocalizedError {
    case esbuildFailed(String)
    case writeFailed(String)
    case missingRuntime

    var errorDescription: String? {
        switch self {
        case .esbuildFailed(let msg):
            return "esbuild failed: \(msg)"
        case .writeFailed(let msg):
            return "Could not write canvas bundle: \(msg)"
        case .missingRuntime:
            return """
            Canvas runtime not found.

            Canvas Library resolves canvas-runtime.esm.js in this order:
            1. App bundle: Resources/CanvasHost/
            2. Source tree: CanvasLibrary/Resources/CanvasHost/
            3. Cursor.app install (local fallback)

            Fix:
            • Install Cursor from https://cursor.com (recommended fallback), or
            • For local development only, place canvas-runtime.esm.js in
              CanvasLibrary/Resources/CanvasHost/ next to host.html

            Redistributing Cursor’s proprietary runtime may be restricted.
            See THIRD_PARTY.md. First-party host files (host.html, canvas-shim.js,
            design-mode.js) always ship with this app.
            """
        }
    }
}

struct CanvasCompiler {
    private let fileManager = FileManager.default

    private static let hostFileNames = ["host.html", "canvas-shim.js", "design-mode.js"]
    private static let runtimeFileName = "canvas-runtime.esm.js"
    private static let allAssetNames = hostFileNames + [runtimeFileName]

    /// Compile `source` into a self-contained host directory ready for WKWebView.
    func compile(source: String, fileName: String = "canvas.tsx") throws -> CanvasCompileResult {
        guard let hostDir = Self.hostAssetsDirectory() else {
            throw CanvasCompilerError.missingRuntime
        }

        let work = fileManager.temporaryDirectory
            .appendingPathComponent("CanvasLibrary-canvas-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)

        for name in Self.allAssetNames {
            let src = hostDir.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: src.path) else {
                throw CanvasCompilerError.writeFailed("Missing host asset: \(name) in \(hostDir.path)")
            }
            try fileManager.copyItem(at: src, to: work.appendingPathComponent(name))
        }

        let safeName: String
        let lower = fileName.lowercased()
        if lower.hasSuffix(".tsx") || lower.hasSuffix(".ts") || lower.hasSuffix(".jsx") || lower.hasSuffix(".js") {
            safeName = fileName
        } else {
            safeName = "\(fileName).tsx"
        }

        let inputURL = work.appendingPathComponent(safeName)
        try source.write(to: inputURL, atomically: true, encoding: .utf8)

        let moduleURL = work.appendingPathComponent("canvas-module.js")
        try runEsbuild(input: inputURL, output: moduleURL)

        var moduleBody = try String(contentsOf: moduleURL, encoding: .utf8)
        // Prefer relative shim path over import maps (more reliable in WKWebView file://)
        moduleBody = moduleBody
            .replacingOccurrences(of: "from \"cursor/canvas\"", with: "from \"./canvas-shim.js\"")
            .replacingOccurrences(of: "from 'cursor/canvas'", with: "from './canvas-shim.js'")
        let patched = """
        /* Canvas Library canvas module */
        const React = globalThis.React;
        \(moduleBody)
        """
        try patched.write(to: moduleURL, atomically: true, encoding: .utf8)

        let hostURL = work.appendingPathComponent("host.html")
        return CanvasCompileResult(workDirectory: work, hostURL: hostURL)
    }

    func cleanup(_ result: CanvasCompileResult) {
        try? fileManager.removeItem(at: result.workDirectory)
    }

    // MARK: - esbuild

    private func runEsbuild(input: URL, output: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let cmd = """
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        npx --yes esbuild@0.25.4 \(shellEscape(input.path)) \
          --outfile=\(shellEscape(output.path)) \
          --format=esm \
          --platform=browser \
          --target=es2020 \
          --jsx=transform \
          --jsx-factory=React.createElement \
          --jsx-fragment=React.Fragment \
          --loader:.tsx=tsx \
          --loader:.ts=ts \
          --loader:.jsx=jsx \
          --loader:.js=js \
          --log-level=error
        """
        process.arguments = ["-lc", cmd]

        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CanvasCompilerError.esbuildFailed(error.localizedDescription)
        }

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0, fileManager.fileExists(atPath: output.path) else {
            throw CanvasCompilerError.esbuildFailed(errText.isEmpty ? "exit \(process.terminationStatus)" : errText)
        }
    }

    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Asset locations

    /// Resolve a directory that contains host.html, canvas-shim.js, design-mode.js,
    /// and canvas-runtime.esm.js.
    ///
    /// Order:
    /// 1. App bundle `Resources/CanvasHost` (if runtime is present)
    /// 2. Source-tree `CanvasLibrary/Resources/CanvasHost` (if runtime is present)
    /// 3. Stage first-party host files + Cursor.app `canvas-runtime.esm.js` into a cache dir
    static func hostAssetsDirectory() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("CanvasHost"),
           hasCompleteHostAssets(bundled) {
            return bundled
        }

        let sourceTree = sourceTreeCanvasHostURL()
        if hasCompleteHostAssets(sourceTree) {
            return sourceTree
        }

        // First-party host pages without a bundled runtime: pair with Cursor install.
        guard let supportDir = hostSupportDirectory(),
              let runtimeURL = cursorRuntimeURL() else {
            return nil
        }
        return stagedHostDirectory(supportDir: supportDir, runtimeURL: runtimeURL)
    }

    /// Directory with first-party host files (runtime optional).
    private static func hostSupportDirectory() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("CanvasHost"),
           hasHostSupportFiles(bundled) {
            return bundled
        }
        let sourceTree = sourceTreeCanvasHostURL()
        if hasHostSupportFiles(sourceTree) {
            return sourceTree
        }
        return nil
    }

    private static func sourceTreeCanvasHostURL() -> URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // CanvasLibrary
            .appendingPathComponent("Resources/CanvasHost")
    }

    private static func hasHostSupportFiles(_ dir: URL) -> Bool {
        let fm = FileManager.default
        return hostFileNames.allSatisfy {
            fm.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
    }

    private static func hasCompleteHostAssets(_ dir: URL) -> Bool {
        let fm = FileManager.default
        return allAssetNames.allSatisfy {
            fm.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
    }

    /// Known Cursor.app install locations for the proprietary canvas runtime.
    private static func cursorRuntimeURL() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let relativePaths = [
            "Contents/Resources/app/extensions/cursor-agent-exec/dist/canvas-runtime/canvas-runtime.esm.js",
            "Contents/Resources/app/extensions/cursor-local-agent-runtime/dist/canvas-runtime/canvas-runtime.esm.js",
        ]
        let appRoots = [
            URL(fileURLWithPath: "/Applications/Cursor.app"),
            home.appendingPathComponent("Applications/Cursor.app"),
        ]
        for root in appRoots {
            for rel in relativePaths {
                let url = root.appendingPathComponent(rel)
                if fm.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }

    /// Copy first-party host files + Cursor runtime into a stable cache directory
    /// so compile() can copy a complete set in one place.
    private static func stagedHostDirectory(supportDir: URL, runtimeURL: URL) -> URL? {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let stage = caches
            .appendingPathComponent("CanvasLibrary", isDirectory: true)
            .appendingPathComponent("CanvasHost", isDirectory: true)

        do {
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)

            for name in hostFileNames {
                let dest = stage.appendingPathComponent(name)
                let src = supportDir.appendingPathComponent(name)
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: src, to: dest)
            }

            let stagedRuntime = stage.appendingPathComponent(runtimeFileName)
            let needsRuntimeCopy: Bool
            if fm.fileExists(atPath: stagedRuntime.path),
               let srcAttrs = try? fm.attributesOfItem(atPath: runtimeURL.path),
               let dstAttrs = try? fm.attributesOfItem(atPath: stagedRuntime.path),
               let srcSize = srcAttrs[.size] as? NSNumber,
               let dstSize = dstAttrs[.size] as? NSNumber,
               srcSize == dstSize {
                needsRuntimeCopy = false
            } else {
                needsRuntimeCopy = true
            }
            if needsRuntimeCopy {
                if fm.fileExists(atPath: stagedRuntime.path) {
                    try fm.removeItem(at: stagedRuntime)
                }
                try fm.copyItem(at: runtimeURL, to: stagedRuntime)
            }

            guard hasCompleteHostAssets(stage) else { return nil }
            return stage
        } catch {
            return nil
        }
    }
}
