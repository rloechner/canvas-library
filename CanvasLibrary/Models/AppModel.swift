//
//  AppModel.swift
//  CanvasSpace
//
//  Working documents companion for Cursor canvases + markdown.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    // MARK: - Library

    @Published private(set) var documents: [WorkingDocument] = []
    @Published var filter: LibraryFilter = .all
    @Published var searchText: String = ""
    @Published var selectedID: WorkingDocument.ID?
    @Published private(set) var spaces: [DocumentSpace] = []
    @Published private(set) var isScanning = false

    // MARK: - Open document buffer

    @Published var openDoc: WorkingDocument?
    @Published var bufferText: String = ""
    @Published var originalText: String = ""
    @Published var viewMode: ViewMode = .preview
    @Published var outline: [OutlineNode] = []
    @Published var isDirty: Bool = false
    /// Unlock preview: click text in the rendered canvas to edit source.
    @Published var isDesignMode: Bool = false

    // MARK: - Canvas / compile

    @Published var isFormatting = false
    @Published var isCompiling = false
    @Published var statusMessage: String?
    private var designRecompileWork: DispatchWorkItem?
    @Published var fontSize: Double = 13
    @Published var showLineNumbers = true
    @Published private(set) var canvasHostURL: URL?
    @Published private(set) var canvasWorkDirectory: URL?
    @Published private(set) var canvasReloadToken = UUID()
    @Published private(set) var canvasError: String?
    @Published private(set) var markdownReloadToken = UUID()
    /// Bumps Monaco document identity after format/revert so content reloads.
    @Published var editorReloadNonce = UUID()

    @Published private(set) var recentIDs: [String] = []
    /// Project names currently expanded in the sidebar outline.
    @Published var expandedProjects: Set<String> = [] {
        didSet { persistExpandedProjects() }
    }

    private let scanner = LibraryScanner()
    private let formatter = TSXFormatter()
    private let outlineParser = TSXOutlineParser()
    private let compiler = CanvasCompiler()
    private var lastCompileResult: CanvasCompileResult?
    private let defaults = UserDefaults.standard
    private let recentKey = "canvaslibrary.recentIDs"
    private let extraSpacesKey = "canvaslibrary.extraSpaces"
    private let expandedProjectsKey = "canvaslibrary.expandedProjects"
    private var didInitializeExpandedProjects = false

    /// Documents matching kind filter + search, before project grouping.
    private var matchingDocuments: [WorkingDocument] {
        documents.filter { doc in
            switch filter {
            case .all: break
            case .canvases: if doc.kind != .canvas { return false }
            case .markdown: if doc.kind != .markdown { return false }
            }
            if searchText.isEmpty { return true }
            let q = searchText.lowercased()
            return doc.fileName.lowercased().contains(q)
                || doc.displayTitle.lowercased().contains(q)
                || doc.projectName.lowercased().contains(q)
        }
    }

    /// Project names in sidebar display order (recent opens, else max modifiedAt, then A–Z).
    var orderedProjectNames: [String] {
        let grouped = Dictionary(grouping: matchingDocuments, by: \.projectName)
        let recentRank: [String: Int] = {
            var rank: [String: Int] = [:]
            for (index, id) in recentIDs.enumerated() {
                guard let doc = documents.first(where: { $0.id == id }) else { continue }
                if rank[doc.projectName] == nil {
                    rank[doc.projectName] = index
                }
            }
            return rank
        }()

        return grouped.keys.sorted { a, b in
            let rankA = recentRank[a] ?? Int.max
            let rankB = recentRank[b] ?? Int.max
            if rankA != rankB { return rankA < rankB }

            let maxA = grouped[a]?.map(\.modifiedAt).max() ?? .distantPast
            let maxB = grouped[b]?.map(\.modifiedAt).max() ?? .distantPast
            if maxA != maxB { return maxA > maxB }

            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    /// Filtered documents in a project, sorted by modifiedAt desc then title A–Z.
    func documents(inProject projectName: String) -> [WorkingDocument] {
        matchingDocuments
            .filter { $0.projectName == projectName }
            .sorted { a, b in
                if a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt }
                return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
            }
    }

    /// Flatten of project-major order — used by goNext/goPrev and list identity.
    var filteredDocuments: [WorkingDocument] {
        orderedProjectNames.flatMap { documents(inProject: $0) }
    }

    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return filteredDocuments.firstIndex(where: { $0.id == selectedID })
    }

    var canGoPrev: Bool {
        guard let i = selectedIndex else { return false }
        return i > 0
    }

    var canGoNext: Bool {
        guard let i = selectedIndex else { return false }
        return i + 1 < filteredDocuments.count
    }

    init() {
        recentIDs = defaults.stringArray(forKey: recentKey) ?? []
        if let saved = defaults.stringArray(forKey: expandedProjectsKey) {
            expandedProjects = Set(saved)
            didInitializeExpandedProjects = true
        }
        loadSpaces()
        refreshLibrary()
    }

    /// Ensure the project that owns the current selection is expanded.
    func expandProjectForSelection() {
        guard let selectedID,
              let doc = documents.first(where: { $0.id == selectedID })
                ?? filteredDocuments.first(where: { $0.id == selectedID })
        else { return }
        expandedProjects.insert(doc.projectName)
    }

    /// After library scan: first launch expands top project only; always expand selection's project.
    func ensureExpandedProjectsAfterScan() {
        let names = orderedProjectNames
        guard !names.isEmpty else { return }

        if !didInitializeExpandedProjects {
            expandedProjects = [names[0]]
            didInitializeExpandedProjects = true
        }

        expandProjectForSelection()
    }

    private func persistExpandedProjects() {
        defaults.set(Array(expandedProjects).sorted(), forKey: expandedProjectsKey)
    }

    // MARK: - Spaces

    private func loadSpaces() {
        var list = [DocumentSpace.allCursorCanvases()]
        if let data = defaults.data(forKey: extraSpacesKey),
           let extra = try? JSONDecoder().decode([DocumentSpace].self, from: data) {
            list.append(contentsOf: extra)
        }
        spaces = list
    }

    private func persistExtraSpaces() {
        let extra = spaces.filter { $0.id != "cursor-all-canvases" }
        if let data = try? JSONEncoder().encode(extra) {
            defaults.set(data, forKey: extraSpacesKey)
        }
    }

    func addFolderSpace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of canvases or markdown docs"
        panel.prompt = "Add Space"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let space = DocumentSpace(
            id: url.path,
            name: url.lastPathComponent,
            path: url.path,
            recursiveCanvases: false
        )
        if !spaces.contains(where: { $0.id == space.id }) {
            spaces.append(space)
            persistExtraSpaces()
            refreshLibrary()
        }
    }

    func removeSpace(_ space: DocumentSpace) {
        guard space.id != "cursor-all-canvases" else { return }
        spaces.removeAll { $0.id == space.id }
        persistExtraSpaces()
        refreshLibrary()
    }

    // MARK: - Library

    func refreshLibrary() {
        isScanning = true
        let spacesSnapshot = spaces
        Task.detached(priority: .userInitiated) {
            let docs = LibraryScanner().scan(spaces: spacesSnapshot)
            await MainActor.run {
                self.documents = docs
                self.isScanning = false
                self.statusMessage = "\(docs.count) documents"
                // Keep selection if still present
                if let id = self.selectedID, !docs.contains(where: { $0.id == id }) {
                    self.selectedID = nil
                    self.closeDocument()
                }
                self.ensureExpandedProjectsAfterScan()
            }
        }
    }

    func select(_ doc: WorkingDocument) {
        selectedID = doc.id
        expandedProjects.insert(doc.projectName)
        open(doc)
    }

    func goNext() {
        guard let i = selectedIndex, i + 1 < filteredDocuments.count else { return }
        select(filteredDocuments[i + 1])
    }

    func goPrev() {
        guard let i = selectedIndex, i > 0 else { return }
        select(filteredDocuments[i - 1])
    }

    // MARK: - Open / buffer

    func open(_ doc: WorkingDocument) {
        do {
            let text = try String(contentsOf: doc.url, encoding: .utf8)
            openDoc = doc
            bufferText = text
            originalText = text
            isDirty = false
            isDesignMode = false
            outline = outlineParser.parse(text)
            canvasError = nil
            viewMode = .preview
            pushRecent(doc.id)

            switch doc.kind {
            case .canvas:
                compileCanvas()
                statusMessage = "Opened canvas · \(doc.displayTitle)"
            case .markdown:
                clearCanvasHost()
                markdownReloadToken = UUID()
                statusMessage = "Opened markdown · \(doc.displayTitle)"
            }
        } catch {
            statusMessage = "Could not open: \(error.localizedDescription)"
            NSAlert(error: error).runModal()
        }
    }

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "tsx"),
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            .plainText,
            .sourceCode,
        ].compactMap { $0 }
        panel.message = "Open a .canvas.tsx or .md file"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let kind: DocumentKind
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".canvas.tsx") {
            kind = .canvas
        } else if name.hasSuffix(".md") || name.hasSuffix(".markdown") {
            kind = .markdown
        } else if name.hasSuffix(".tsx") {
            kind = .canvas
        } else {
            kind = .markdown
        }

        let doc = WorkingDocument(
            id: url.path,
            urlPath: url.path,
            kind: kind,
            projectName: url.deletingLastPathComponent().lastPathComponent,
            fileName: url.lastPathComponent,
            modifiedAt: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date(),
            fileSize: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        )
        select(doc)
    }

    func closeDocument() {
        openDoc = nil
        bufferText = ""
        originalText = ""
        isDirty = false
        isDesignMode = false
        outline = []
        clearCanvasHost()
    }

    func setDesignMode(_ on: Bool) {
        guard openDoc?.kind == .canvas else {
            isDesignMode = false
            return
        }
        isDesignMode = on
        if on {
            viewMode = .preview
            statusMessage = "Preview unlocked — click text to edit"
        } else {
            statusMessage = isDirty ? "Unsaved changes" : "Preview locked"
            // Refresh preview from current buffer when locking
            if openDoc?.kind == .canvas, !isCompiling {
                scheduleDesignRecompile(immediate: true)
            }
        }
    }

    /// Apply a text edit that originated from unlocked preview.
    func applyPreviewTextEdit(oldText: String, newText: String) {
        guard openDoc?.kind == .canvas else { return }
        let result = SourceTextRewriter.replace(oldText: oldText, with: newText, in: bufferText)
        if result.replaced {
            updateBuffer(result.text)
            editorReloadNonce = UUID()
            let multi = result.occurrenceCount > 1 ? " (first of \(result.occurrenceCount) matches)" : ""
            statusMessage = "Preview edit → source\(multi)"
            scheduleDesignRecompile(immediate: false)
        } else {
            statusMessage = "Couldn't map “\(String(oldText.prefix(40)))” to source — edit in Source"
        }
    }

    private func scheduleDesignRecompile(immediate: Bool) {
        designRecompileWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.compileCanvasPreservingDesignMode()
        }
        designRecompileWork = work
        if immediate {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }

    /// Recompile without forcing design mode off.
    private func compileCanvasPreservingDesignMode() {
        let keepDesign = isDesignMode
        compileCanvas()
        // compileCanvas async; re-enable design after ready via canvasDidReady
        if keepDesign {
            isDesignMode = true
        }
    }

    func updateBuffer(_ newText: String) {
        guard bufferText != newText else { return }
        bufferText = newText
        isDirty = bufferText != originalText
        if openDoc?.kind == .canvas {
            outline = outlineParser.parse(newText)
        }
        if isDirty {
            statusMessage = "Unsaved changes"
        }
    }

    /// Discard buffer edits and restore last loaded/saved text.
    func revertDocument() {
        guard isDirty else { return }
        let alert = NSAlert()
        alert.messageText = "Revert unsaved changes?"
        alert.informativeText = "Your edits will be discarded and the last saved version restored."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        bufferText = originalText
        isDirty = false
        if openDoc?.kind == .canvas {
            outline = outlineParser.parse(originalText)
        } else {
            markdownReloadToken = UUID()
        }
        // Bump identity so Monaco reloads content even if string equal-check races
        editorReloadNonce = UUID()
        statusMessage = "Reverted"
    }

    // MARK: - Save / format

    func saveDocument() {
        guard let doc = openDoc else { return }
        do {
            try bufferText.write(to: doc.url, atomically: true, encoding: .utf8)
            originalText = bufferText
            isDirty = false
            statusMessage = "Saved"
            refreshLibrary()
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            NSAlert(error: error).runModal()
        }
    }

    func formatDocument() {
        guard openDoc != nil else { return }
        isFormatting = true
        defer { isFormatting = false }

        if openDoc?.kind == .markdown {
            // Light markdown normalize: trim trailing spaces, ensure final newline
            var t = bufferText.replacingOccurrences(of: "\r\n", with: "\n")
            let lines = t.split(separator: "\n", omittingEmptySubsequences: false).map {
                $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            }
            t = lines.joined(separator: "\n")
            if !t.hasSuffix("\n") { t += "\n" }
            updateBuffer(t)
            markdownReloadToken = UUID()
            editorReloadNonce = UUID()
            statusMessage = "Formatted markdown"
            return
        }

        let result = formatter.format(bufferText)
        updateBuffer(result.output)
        editorReloadNonce = UUID()
        statusMessage = result.engineDescription
        if openDoc?.kind == .canvas {
            // Don't auto-compile after format — user can reload preview
        }
    }

    /// Language id for the Monaco editor.
    var editorLanguage: String {
        guard let doc = openDoc else { return "typescript" }
        switch doc.kind {
        case .markdown: return "markdown"
        case .canvas: return "typescript"
        }
    }

    func recompileOrRefresh() {
        guard let doc = openDoc else { return }
        switch doc.kind {
        case .canvas:
            compileCanvas()
        case .markdown:
            markdownReloadToken = UUID()
            statusMessage = "Preview refreshed"
        }
    }

    func copyBuffer() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bufferText, forType: .string)
        statusMessage = "Copied"
    }

    func revealInFinder() {
        guard let doc = openDoc else { return }
        NSWorkspace.shared.activateFileViewerSelecting([doc.url])
    }

    func jumpToOutline(_ node: OutlineNode) {
        viewMode = .source
    }

    // MARK: - Canvas compile

    func compileCanvas() {
        guard openDoc?.kind == .canvas else { return }
        isCompiling = true
        canvasError = nil
        statusMessage = "Compiling canvas…"
        let source = bufferText
        let fileName = openDoc?.fileName ?? "canvas.tsx"
        let compiler = self.compiler

        Task.detached(priority: .userInitiated) {
            do {
                let result = try compiler.compile(source: source, fileName: fileName)
                await MainActor.run {
                    self.applyCompileResult(result)
                }
            } catch {
                await MainActor.run {
                    self.isCompiling = false
                    self.canvasError = error.localizedDescription
                    self.statusMessage = "Compile failed"
                    self.viewMode = .source
                }
            }
        }
    }

    private func applyCompileResult(_ result: CanvasCompileResult) {
        if let previous = lastCompileResult {
            compiler.cleanup(previous)
        }
        lastCompileResult = result
        canvasWorkDirectory = result.workDirectory
        canvasHostURL = result.hostURL
        canvasReloadToken = UUID()
        isCompiling = false
        statusMessage = "Canvas ready"
        if viewMode != .source {
            viewMode = .preview
        }
    }

    private func clearCanvasHost() {
        if let previous = lastCompileResult {
            compiler.cleanup(previous)
        }
        lastCompileResult = nil
        canvasHostURL = nil
        canvasWorkDirectory = nil
        canvasError = nil
    }

    func canvasDidReady() {
        canvasError = nil
        isCompiling = false
        if isDesignMode {
            statusMessage = "Preview unlocked — click text to edit"
        } else if isDirty {
            statusMessage = "Canvas rendered · unsaved changes"
        } else {
            statusMessage = "Canvas rendered"
        }
    }

    func canvasDidFail(_ message: String) {
        canvasError = message
        statusMessage = "Canvas error"
        isCompiling = false
    }

    // MARK: - Recent

    private func pushRecent(_ id: String) {
        var ids = recentIDs.filter { $0 != id }
        ids.insert(id, at: 0)
        if ids.count > 20 { ids = Array(ids.prefix(20)) }
        recentIDs = ids
        defaults.set(ids, forKey: recentKey)
    }

    var recentDocuments: [WorkingDocument] {
        recentIDs.compactMap { id in documents.first(where: { $0.id == id }) }
    }

    // MARK: - Helpers

    static var supportedOpenTypes: [UTType] {
        ["tsx", "md", "markdown", "jsx", "ts", "js"].compactMap { UTType(filenameExtension: $0) }
        + [.plainText, .sourceCode]
    }
}
