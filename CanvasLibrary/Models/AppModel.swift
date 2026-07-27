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
    /// Bumps whenever the library set changes so sidebar Lists reliably re-render.
    @Published private(set) var libraryEpoch: UInt64 = 0

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
    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: fontSizeKey) }
    }
    @Published var showLineNumbers: Bool {
        didSet { defaults.set(showLineNumbers, forKey: lineNumbersKey) }
    }
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
    /// Folder expansion keys: `"projectName//relative/folder/path"`.
    @Published var expandedFolders: Set<String> = [] {
        didSet { persistExpandedFolders() }
    }

    private let scanner = LibraryScanner()
    private let outlineParser = TSXOutlineParser()
    private let compiler = CanvasCompiler()
    private var lastCompileResult: CanvasCompileResult?
    private let defaults = UserDefaults.standard
    private let recentKey = "canvaslibrary.recentIDs"
    private let extraSpacesKey = "canvaslibrary.extraSpaces"
    private let expandedProjectsKey = "canvaslibrary.expandedProjects"
    private let expandedFoldersKey = "canvaslibrary.expandedFolders"
    private let fontSizeKey = "canvaslibrary.fontSize"
    private let lineNumbersKey = "canvaslibrary.showLineNumbers"
    private var didInitializeExpandedProjects = false
    /// Avoid stacking concurrent full-library scans.
    private var scanGeneration: UInt64 = 0
    private var didScheduleInitialScan = false
    /// Drop stale canvas compile results after fast document switches.
    private var compileGeneration: UInt64 = 0
    private var formatGeneration: UInt64 = 0

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
                || doc.relativePath.lowercased().contains(q)
                || doc.folderPath.lowercased().contains(q)
        }
    }

    /// Project names in sidebar display order — stable A–Z (no “recent project jumps”).
    var orderedProjectNames: [String] {
        let names = Set(matchingDocuments.map(\.projectName))
        return names.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// Filtered documents in a project (unsorted raw match set for tree building).
    func documents(inProject projectName: String) -> [WorkingDocument] {
        matchingDocuments.filter { $0.projectName == projectName }
    }

    /// Finder-like tree for a project: folders (only those with matches) then files, A–Z.
    func libraryTree(for projectName: String) -> [LibraryTreeNode] {
        LibraryTreeBuilder.build(docs: documents(inProject: projectName), projectName: projectName)
    }

    /// Flatten of project-major, tree-order — used by goNext/goPrev.
    var filteredDocuments: [WorkingDocument] {
        orderedProjectNames.flatMap { project in
            flattenTree(libraryTree(for: project))
        }
    }

    private func flattenTree(_ nodes: [LibraryTreeNode]) -> [WorkingDocument] {
        var result: [WorkingDocument] = []
        for node in nodes {
            switch node {
            case .folder(_, _, _, let children, _):
                result.append(contentsOf: flattenTree(children))
            case .file(let doc):
                result.append(doc)
            }
        }
        return result
    }

    static func folderExpansionKey(project: String, folderPath: String) -> String {
        "\(project)//\(folderPath)"
    }

    func isFolderExpanded(project: String, folderPath: String) -> Bool {
        if !searchText.isEmpty { return true }
        return expandedFolders.contains(Self.folderExpansionKey(project: project, folderPath: folderPath))
    }

    func setFolderExpanded(project: String, folderPath: String, expanded: Bool) {
        guard searchText.isEmpty else { return }
        let key = Self.folderExpansionKey(project: project, folderPath: folderPath)
        if expanded {
            expandedFolders.insert(key)
        } else {
            expandedFolders.remove(key)
        }
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
        let storedFont = defaults.object(forKey: fontSizeKey) as? Double
        fontSize = storedFont.map { min(20, max(11, $0)) } ?? 13
        if defaults.object(forKey: lineNumbersKey) != nil {
            showLineNumbers = defaults.bool(forKey: lineNumbersKey)
        } else {
            showLineNumbers = true
        }
        recentIDs = defaults.stringArray(forKey: recentKey) ?? []
        if let saved = defaults.stringArray(forKey: expandedProjectsKey) {
            expandedProjects = Set(saved)
            // Only treat as initialized if something is actually expanded;
            // an empty saved set still needs a first-load default expand.
            didInitializeExpandedProjects = !saved.isEmpty
        }
        if let savedFolders = defaults.stringArray(forKey: expandedFoldersKey) {
            expandedFolders = Set(savedFolders)
        }
        loadSpaces()
        // Do NOT scan here. Publishing @Published during @StateObject init
        // often drops the first UI update — sidebar stays empty until a later
        // user-driven refresh (e.g. Add Folder). Scan from ensureLibraryLoaded().
    }

    /// Call from the root view's onAppear. Safe to call repeatedly.
    func ensureLibraryLoaded() {
        if !didScheduleInitialScan {
            didScheduleInitialScan = true
            refreshLibrary()
            return
        }
        // If the first scan somehow never applied, try again when UI appears.
        if documents.isEmpty, !isScanning {
            refreshLibrary()
        }
    }

    /// Ensure the project (and ancestor folders) that own the current selection are expanded.
    func expandProjectForSelection() {
        guard let selectedID,
              let doc = documents.first(where: { $0.id == selectedID })
                ?? filteredDocuments.first(where: { $0.id == selectedID })
        else { return }
        expandAncestors(of: doc)
    }

    /// Expand project + every parent folder leading to `doc`.
    func expandAncestors(of doc: WorkingDocument) {
        expandedProjects.insert(doc.projectName)
        var path = doc.folderPath
        while !path.isEmpty {
            expandedFolders.insert(Self.folderExpansionKey(project: doc.projectName, folderPath: path))
            path = (path as NSString).deletingLastPathComponent
            if path == "." { path = "" }
        }
    }

    /// After library scan: first launch expands top project only; always expand selection's path.
    func ensureExpandedProjectsAfterScan() {
        let names = orderedProjectNames
        guard !names.isEmpty else { return }

        // Drop expansion keys for projects that no longer exist.
        let nameSet = Set(names)
        expandedProjects = expandedProjects.intersection(nameSet)

        if !didInitializeExpandedProjects || expandedProjects.isEmpty {
            expandedProjects = [names[0]]
            didInitializeExpandedProjects = true
        }

        expandProjectForSelection()
    }

    private func persistExpandedProjects() {
        defaults.set(Array(expandedProjects).sorted(), forKey: expandedProjectsKey)
    }

    private func persistExpandedFolders() {
        defaults.set(Array(expandedFolders).sorted(), forKey: expandedFoldersKey)
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
        scanGeneration &+= 1
        let generation = scanGeneration
        isScanning = true
        let spacesSnapshot = spaces

        Task.detached(priority: .userInitiated) {
            let docs = LibraryScanner().scan(spaces: spacesSnapshot)
            await MainActor.run {
                // Ignore stale scans if a newer refresh was started.
                guard generation == self.scanGeneration else { return }
                self.applyLibraryScan(docs)
            }
        }
    }

    private func applyLibraryScan(_ docs: [WorkingDocument]) {
        var merged = docs
        // Keep an open file that lives outside scanned spaces visible in the list.
        if let open = openDoc, !merged.contains(where: { $0.id == open.id }) {
            merged.append(open)
        }
        documents = merged
        isScanning = false
        libraryEpoch &+= 1
        statusMessage = "\(docs.count) documents"

        if let id = selectedID, !merged.contains(where: { $0.id == id }) {
            if isDirty, let open = openDoc {
                // Never wipe an unsaved buffer just because rescan missed the path.
                selectedID = open.id
                if !documents.contains(where: { $0.id == open.id }) {
                    documents.append(open)
                }
            } else if openDoc != nil {
                // Keep editing even if the row fell out of the scan set.
                selectedID = openDoc?.id
            } else {
                selectedID = nil
                closeDocument()
            }
        }
        ensureExpandedProjectsAfterScan()
    }

    func select(_ doc: WorkingDocument) {
        if openDoc?.id == doc.id {
            selectedID = doc.id
            expandAncestors(of: doc)
            return
        }
        guard confirmNavigateAwayIfDirty() else {
            selectedID = openDoc?.id
            return
        }
        selectedID = doc.id
        expandAncestors(of: doc)
        open(doc)
    }

    /// Save / Don't Save / Cancel when leaving a dirty buffer.
    @discardableResult
    func confirmNavigateAwayIfDirty() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Unsaved changes"
        alert.informativeText = "Save changes before switching documents?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveDocument()
            return !isDirty
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
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
            // Surface externally opened files in the sidebar without a full rescan.
            if !documents.contains(where: { $0.id == doc.id }) {
                documents.append(doc)
                libraryEpoch &+= 1
            }

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
            relativePath: url.lastPathComponent,
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
            // In-place metadata update — avoid full rescan (sidebar thrash + close races).
            touchOpenDocumentMetadata()
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            NSAlert(error: error).runModal()
        }
    }

    private func touchOpenDocumentMetadata() {
        guard var doc = openDoc else { return }
        let values = try? doc.url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        doc.modifiedAt = values?.contentModificationDate ?? Date()
        doc.fileSize = Int64(values?.fileSize ?? 0)
        openDoc = doc
        if let idx = documents.firstIndex(where: { $0.id == doc.id }) {
            documents[idx] = doc
        } else {
            documents.append(doc)
            libraryEpoch &+= 1
        }
    }

    func formatDocument() {
        guard openDoc != nil else { return }
        formatGeneration &+= 1
        let generation = formatGeneration
        let kind = openDoc?.kind
        let source = bufferText
        let docID = openDoc?.id
        isFormatting = true
        statusMessage = "Formatting…"

        Task.detached(priority: .userInitiated) {
            let result: FormatResult
            if kind == .markdown {
                var t = source.replacingOccurrences(of: "\r\n", with: "\n")
                let lines = t.split(separator: "\n", omittingEmptySubsequences: false).map {
                    $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
                }
                t = lines.joined(separator: "\n")
                if !t.hasSuffix("\n") { t += "\n" }
                result = FormatResult(output: t, engineDescription: "Formatted markdown")
            } else {
                result = TSXFormatter().format(source)
            }

            await MainActor.run {
                guard generation == self.formatGeneration, self.openDoc?.id == docID else {
                    self.isFormatting = false
                    return
                }
                self.updateBuffer(result.output)
                self.editorReloadNonce = UUID()
                if kind == .markdown {
                    self.markdownReloadToken = UUID()
                }
                self.isFormatting = false
                self.statusMessage = result.engineDescription
            }
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
        compileGeneration &+= 1
        let generation = compileGeneration
        let docID = openDoc?.id
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
                    guard generation == self.compileGeneration, self.openDoc?.id == docID else {
                        compiler.cleanup(result)
                        return
                    }
                    self.applyCompileResult(result)
                }
            } catch {
                await MainActor.run {
                    guard generation == self.compileGeneration, self.openDoc?.id == docID else { return }
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
