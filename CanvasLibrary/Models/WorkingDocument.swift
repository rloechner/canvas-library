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
    var modifiedAt: Date
    var fileSize: Int64

    var url: URL { URL(fileURLWithPath: urlPath) }

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
        "\(projectName) · \(kind.title)"
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
