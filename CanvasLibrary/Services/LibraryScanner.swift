//
//  LibraryScanner.swift
//  Canvas Library
//

import Foundation

struct LibraryScanner {
    private let fileManager = FileManager.default

    func scan(spaces: [DocumentSpace]) -> [WorkingDocument] {
        var byPath: [String: WorkingDocument] = [:]

        for space in spaces {
            let found = space.recursiveCanvases
                ? scanCursorProjectsRoot(space.url, spaceID: space.id)
                : scanDirectory(space.url, projectName: space.name, spaceID: space.id)

            for doc in found {
                byPath[doc.urlPath] = doc
            }
        }

        return byPath.values.sorted { a, b in
            if a.modifiedAt != b.modifiedAt {
                return a.modifiedAt > b.modifiedAt
            }
            return a.fileName.localizedCaseInsensitiveCompare(b.fileName) == .orderedAscending
        }
    }

    /// ~/.cursor/projects/*/canvases/**/*.{canvas.tsx,md}
    private func scanCursorProjectsRoot(_ root: URL, spaceID: String) -> [WorkingDocument] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        var results: [WorkingDocument] = []
        guard let projects = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for projectURL in projects {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: projectURL.path, isDirectory: &isDir), isDir.boolValue
            else { continue }

            let canvases = projectURL.appendingPathComponent("canvases")
            guard fileManager.fileExists(atPath: canvases.path) else { continue }

            let projectName = friendlyProjectName(projectURL.lastPathComponent)
            results.append(contentsOf: scanDirectory(canvases, projectName: projectName, spaceID: spaceID))
        }
        return results
    }

    /// Recursively finds .canvas.tsx / .md under `dir`, preserving relative paths for the sidebar tree.
    private func scanDirectory(_ dir: URL, projectName: String, spaceID: String) -> [WorkingDocument] {
        let root = dir.standardizedFileURL
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey,
                .isDirectoryKey,
            ],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var docs: [WorkingDocument] = []
        let rootPath = root.path
        let skipDirNames: Set<String> = [
            "node_modules", ".git", "dist", "build", "DerivedData",
            ".build", "Pods", "Carthage", ".next", "coverage",
            "xcuserdata", ".turbo", ".cache",
        ]

        for case let item as URL in enumerator {
            let url = item.standardizedFileURL
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .contentModificationDateKey,
                .fileSizeKey,
            ])

            if values?.isDirectory == true {
                if skipDirNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile != false else { continue }
            guard let kind = kind(for: url) else { continue }

            let relativePath = relativePath(of: url.path, under: rootPath)
            let modified = values?.contentModificationDate ?? Date.distantPast
            let size = Int64(values?.fileSize ?? 0)

            docs.append(
                WorkingDocument(
                    id: url.path,
                    urlPath: url.path,
                    kind: kind,
                    projectName: projectName,
                    fileName: url.lastPathComponent,
                    relativePath: relativePath,
                    spaceID: spaceID,
                    modifiedAt: modified,
                    fileSize: size
                )
            )
        }
        return docs
    }

    private func relativePath(of fullPath: String, under rootPath: String) -> String {
        if fullPath == rootPath { return "" }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if fullPath.hasPrefix(prefix) {
            return String(fullPath.dropFirst(prefix.count))
        }
        return (fullPath as NSString).lastPathComponent
    }

    private func kind(for url: URL) -> DocumentKind? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".canvas.tsx") { return .canvas }
        if name.hasSuffix(".md") || name.hasSuffix(".markdown") { return .markdown }
        return nil
    }

    /// Users-ryan-srv-shortyawards → shortyawards
    private func friendlyProjectName(_ raw: String) -> String {
        if raw.hasPrefix("Users-") {
            let parts = raw.split(separator: "-")
            // Users-ryan-srv-shortyawards or Users-ryan-Documents-Apps-stacker
            if let srvIdx = parts.firstIndex(of: "srv"), srvIdx + 1 < parts.endIndex {
                return parts[(srvIdx + 1)...].joined(separator: "-")
            }
            if let docsIdx = parts.firstIndex(of: "Documents"), docsIdx + 1 < parts.endIndex {
                return parts[(docsIdx + 1)...].joined(separator: "/")
            }
        }
        // Numeric temp project ids — keep enough of the id to avoid collisions.
        if raw.allSatisfy(\.isNumber) {
            let tail = raw.count > 6 ? raw.suffix(6) : raw.suffix(raw.count)
            return "project \(tail)"
        }
        // Cursor temp workspaces under /var/folders — unique by trailing segment.
        if raw.hasPrefix("var-folders") {
            let tail = raw.split(separator: "-").suffix(2).joined(separator: "-")
            return tail.isEmpty ? "temp \(raw.suffix(8))" : "temp · \(tail)"
        }
        return raw
    }
}
