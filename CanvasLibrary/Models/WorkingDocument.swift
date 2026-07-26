//
//  WorkingDocument.swift
//  CanvasSpace (TSXPretty)
//
//  A working Cursor document: canvas or markdown.
//

import Foundation

enum DocumentKind: String, Codable, CaseIterable, Identifiable {
    case canvas
    case markdown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .canvas: return "Canvas"
        case .markdown: return "Markdown"
        }
    }

    var systemImage: String {
        switch self {
        case .canvas: return "rectangle.3.group"
        case .markdown: return "doc.richtext"
        }
    }

    var badgeColorName: String {
        switch self {
        case .canvas: return "purple"
        case .markdown: return "blue"
        }
    }
}

/// One file in the user's working set.
struct WorkingDocument: Identifiable, Hashable, Codable {
    let id: String
    let urlPath: String
    let kind: DocumentKind
    let projectName: String
    let fileName: String
    /// Path relative to the project/space scan root, e.g. `"notes/plan.md"` or `"home.canvas.tsx"`.
    let relativePath: String
    var modifiedAt: Date
    var fileSize: Int64

    var url: URL { URL(fileURLWithPath: urlPath) }

    /// Parent folder of `relativePath`, or `""` when the file sits at the project root.
    var folderPath: String {
        let parent = (relativePath as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }

    var displayTitle: String {
        if fileName.hasSuffix(".canvas.tsx") {
            return String(fileName.dropLast(".canvas.tsx".count))
                .replacingOccurrences(of: "-", with: " ")
        }
        if fileName.hasSuffix(".md") {
            return String(fileName.dropLast(3))
                .replacingOccurrences(of: "-", with: " ")
        }
        return fileName
    }

    var subtitle: String {
        if folderPath.isEmpty {
            return "\(projectName) · \(kind.title)"
        }
        return "\(projectName)/\(folderPath) · \(kind.title)"
    }
}

// MARK: - Library tree (Finder-like)

/// A node in the project → folder → file outline.
enum LibraryTreeNode: Identifiable, Hashable {
    case folder(id: String, name: String, relativePath: String, children: [LibraryTreeNode], fileCount: Int)
    case file(WorkingDocument)

    var id: String {
        switch self {
        case .folder(let id, _, _, _, _): return id
        case .file(let doc): return doc.id
        }
    }

    var fileCount: Int {
        switch self {
        case .folder(_, _, _, _, let count): return count
        case .file: return 1
        }
    }
}

enum LibraryTreeBuilder {
    /// Build a Finder-style tree from documents that already share one project.
    /// Only folders that contain matching files (directly or nested) appear.
    static func build(docs: [WorkingDocument], projectName: String) -> [LibraryTreeNode] {
        // folderPath → files living directly in that folder
        var filesByFolder: [String: [WorkingDocument]] = [:]
        // all folder paths that must exist (ancestors of every file)
        var folderPaths = Set<String>()

        for doc in docs {
            let folder = doc.folderPath
            filesByFolder[folder, default: []].append(doc)
            var path = folder
            while !path.isEmpty {
                folderPaths.insert(path)
                path = (path as NSString).deletingLastPathComponent
                if path == "." { path = "" }
            }
        }

        // parent → child folder names
        var childFolders: [String: Set<String>] = [:]
        for path in folderPaths {
            let parent = (path as NSString).deletingLastPathComponent
            let parentKey = parent == "." ? "" : parent
            let name = (path as NSString).lastPathComponent
            childFolders[parentKey, default: []].insert(name)
        }

        func sortFiles(_ files: [WorkingDocument]) -> [WorkingDocument] {
            files.sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        }

        func buildLevel(parentPath: String) -> [LibraryTreeNode] {
            var nodes: [LibraryTreeNode] = []

            let folderNames = (childFolders[parentPath] ?? []).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            for name in folderNames {
                let path = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
                let children = buildLevel(parentPath: path)
                let count = children.reduce(0) { $0 + $1.fileCount }
                let id = "folder:\(projectName)/\(path)"
                nodes.append(.folder(id: id, name: name, relativePath: path, children: children, fileCount: count))
            }

            for doc in sortFiles(filesByFolder[parentPath] ?? []) {
                nodes.append(.file(doc))
            }

            return nodes
        }

        return buildLevel(parentPath: "")
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case canvases
    case markdown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .canvases: return "Canvases"
        case .markdown: return "Markdown"
        }
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case preview
    case source

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preview: return "Preview"
        case .source: return "Source"
        }
    }
}

/// A root location that contributes documents to the library.
struct DocumentSpace: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var path: String
    /// If true, scan recursively for canvases/md (Cursor projects root).
    var recursiveCanvases: Bool

    var url: URL { URL(fileURLWithPath: path) }

    static func allCursorCanvases() -> DocumentSpace {
        let root = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cursor/projects")
        return DocumentSpace(
            id: "cursor-all-canvases",
            name: "All Cursor canvases",
            path: root.path,
            recursiveCanvases: true
        )
    }
}
