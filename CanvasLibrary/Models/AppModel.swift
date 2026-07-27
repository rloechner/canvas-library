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
    @Published var filter: LibraryFilter = .all {
        didSet { defaults.set(filter.rawValue, forKey: libraryFilterKey) }
    }
    @Published var searchText: String = ""
    @Published var selectedID: WorkingDocument.ID?
    @Published private(set) var spaces: [DocumentSpace] = []
    @Published private(set) var needsSetup: Bool = false
    @Published private(set) var isScanning = false
    /// Bumps whenever the library set changes so sidebar Lists reliably re-render.
    @Published private(set) var libraryEpoch: UInt64 = 0
    /// Stable A–Z project names for the sidebar (published explicitly for SwiftUI).
    @Published private(set) var sidebarProjectNames: [String] = []

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
    /// Preferred project order in the sidebar (names not in the list sort A–Z after).
    @Published var projectOrder: [String] = [] {
        didSet { defaults.set(projectOrder, forKey: projectOrderKey) }
    }
    /// Projects hidden from the sidebar (not deleted from disk).
    @Published var hiddenProjects: Set<String> = [] {
        didSet { defaults.set(Array(hiddenProjects).sorted(), forKey: hiddenProjectsKey) }
    }
    /// Hidden folders: `"projectName//relative/folder"` (hides that folder and descendants).
    @Published var excludedFolders: Set<String> = [] {
        didSet { defaults.set(Array(excludedFolders).sorted(), forKey: excludedFoldersKey) }
    }

    private let scanner = LibraryScanner()
    private let outlineParser = TSXOutlineParser()
    private let compiler = CanvasCompiler()
    private var lastCompileResult: CanvasCompileResult?
    private let defaults = UserDefaults.standard
    private let recentKey = "canvaslibrary.recentIDs"
    /// Legacy key — read-only for migration; new saves use librarySpacesKey.
    private let extraSpacesKey = "canvaslibrary.extraSpaces"
    private let librarySpacesKey = "canvaslibrary.librarySpaces"
    private let didCompleteSetupKey = "canvaslibrary.didCompleteSetup"
    private let libraryFilterKey = "canvaslibrary.libraryFilter"
    private let expandedProjectsKey = "canvaslibrary.expandedProjects"
    private let expandedFoldersKey = "canvaslibrary.expandedFolders"
    private let projectOrderKey = "canvaslibrary.projectOrder"
    private let hiddenProjectsKey = "canvaslibrary.hiddenProjects"
    private let excludedFoldersKey = "canvaslibrary.excludedFolders"
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
            if hiddenProjects.contains(doc.projectName) { return false }
            if isDocumentExcluded(doc) { return false }
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

    private func isDocumentExcluded(_ doc: WorkingDocument) -> Bool {
        for key in excludedFolders {
            // Stored as "project//folder/path"
            guard let range = key.range(of: "//") else { continue }
            let project = String(key[..<range.lowerBound])
            let folder = String(key[range.upperBound...])
            guard project == doc.projectName, !folder.isEmpty else { continue }
            if doc.folderPath == folder || doc.folderPath.hasPrefix(folder + "/") { return true }
            if doc.relativePath == folder || doc.relativePath.hasPrefix(folder + "/") { return true }
        }
        return false
    }

    /// Project names in sidebar display order (custom order, then A–Z).
    var orderedProjectNames: [String] {
        orderedNames(from: Set(matchingDocuments.map(\.projectName)))
    }

    private func orderedNames(from names: Set<String>) -> [String] {
        var remaining = names
        var result: [String] = []
        for name in projectOrder where remaining.contains(name) {
            result.append(name)
            remaining.remove(name)
        }
        let rest = remaining.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        result.append(contentsOf: rest)
        return result
    }

    /// Filtered documents in a project (unsorted raw match set for tree building).
    func documents(inProject projectName: String) -> [WorkingDocument] {
        matchingDocuments.filter { $0.projectName == projectName }
    }

    /// Finder-like tree for a project: folders (only those with matches) then files, A–Z.
    func libraryTree(for projectName: String) -> [LibraryTreeNode] {
        LibraryTreeBuilder.build(docs: documents(inProject: projectName), projectName: projectName)
    }

    static func folderExclusionKey(project: String, folderPath: String) -> String {
        "\(project)//\(folderPath)"
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
        projectOrder = defaults.stringArray(forKey: projectOrderKey) ?? []
        if let hidden = defaults.stringArray(forKey: hiddenProjectsKey) {
            hiddenProjects = Set(hidden)
        }
        if let excluded = defaults.stringArray(forKey: excludedFoldersKey) {
            excludedFolders = Set(excluded)
        }
        if let raw = defaults.string(forKey: libraryFilterKey),
           let savedFilter = LibraryFilter(rawValue: raw) {
            filter = savedFilter
        }
        loadSpaces()
        // Do NOT scan here. Publishing @Published during @StateObject init
        // often drops the first UI update — sidebar stays empty until a later
        // user-driven refresh (e.g. Add Folder). Scan from ensureLibraryLoaded().
    }

    /// Call from the root view's onAppear. Safe to call repeatedly.
    func ensureLibraryLoaded() {
        // First-launch / setup incomplete: do not auto-scan.
        if needsSetup {
            debugLog("ensureLibraryLoaded skip — needsSetup")
            return
        }
        // After setup with no spaces, avoid infinite empty-library retries.
        if spaces.isEmpty {
            debugLog("ensureLibraryLoaded skip — no spaces configured")
            return
        }
        if !didScheduleInitialScan {
            didScheduleInitialScan = true
            refreshLibrary()
            // First-frame races: if the initial async apply is dropped, retry once
            // (only when spaces are non-empty — empty spaces are intentional).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                if self.documents.isEmpty, !self.isScanning, !self.spaces.isEmpty {
                    self.debugLog("ensureLibraryLoaded retry — still empty after 0.6s")
                    self.refreshLibrary()
                }
            }
            return
        }
        if documents.isEmpty, !isScanning, !spaces.isEmpty {
            refreshLibrary()
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let path = "/tmp/canvaslibrary-debug.log"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path),
               let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        #endif
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

    /// After library scan: expand projects so the sidebar is visibly populated.
    func ensureExpandedProjectsAfterScan() {
        let names = sidebarProjectNames.isEmpty ? orderedProjectNames : sidebarProjectNames
        guard !names.isEmpty else { return }

        // Always expand every project after a scan so the first paint shows
        // documents — not an empty-looking rail of collapsed folders. Users can
        // still collapse; the next rescan re-opens for discoverability.
        let nameSet = Set(names)
        expandedProjects = nameSet
        didInitializeExpandedProjects = true

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
        let didSetup = defaults.bool(forKey: didCompleteSetupKey)

        if didSetup {
            // User-controlled spaces only (may be empty).
            if let data = defaults.data(forKey: librarySpacesKey),
               let saved = try? JSONDecoder().decode([DocumentSpace].self, from: data) {
                spaces = saved
            } else {
                spaces = []
            }
            needsSetup = false
            debugLog("loadSpaces setup complete spaces=\(spaces.count)")
            return
        }

        // Legacy signals: prior installs always auto-injected cursor + may have extras.
        let legacyExtras: [DocumentSpace] = {
            guard let data = defaults.data(forKey: extraSpacesKey),
                  let extra = try? JSONDecoder().decode([DocumentSpace].self, from: data)
            else { return [] }
            return extra
        }()
        let hasLegacySignals =
            !legacyExtras.isEmpty
            || !recentIDs.isEmpty
            || !expandedProjects.isEmpty
            || !projectOrder.isEmpty

        if hasLegacySignals {
            // One-time migration from pre-setup model.
            if !legacyExtras.isEmpty {
                spaces = legacyExtras
            } else {
                // Old default was always-on cursor scan — promote once for returning users.
                spaces = [DocumentSpace.allCursorCanvases()]
            }
            persistSpaces()
            defaults.set(true, forKey: didCompleteSetupKey)
            needsSetup = false
            debugLog("loadSpaces migrated legacy spaces=\(spaces.count)")
            return
        }

        // True first launch: empty library, user must opt in.
        spaces = []
        needsSetup = true
        debugLog("loadSpaces first launch — needsSetup")
    }

    private func persistSpaces() {
        if let data = try? JSONEncoder().encode(spaces) {
            defaults.set(data, forKey: librarySpacesKey)
        }
    }

    /// Mark setup complete. Refresh only when spaces are configured.
    func completeSetup() {
        defaults.set(true, forKey: didCompleteSetupKey)
        needsSetup = false
        if !spaces.isEmpty {
            refreshLibrary()
        }
        debugLog("completeSetup spaces=\(spaces.count)")
    }

    /// Finish setup with an empty library (no scan thrash).
    func completeSetupEmpty() {
        spaces = []
        persistSpaces()
        defaults.set(true, forKey: didCompleteSetupKey)
        needsSetup = false
        debugLog("completeSetupEmpty")
    }

    /// Opt-in: append the Cursor projects recursive space if missing.
    func addCursorCanvasesSpace() {
        let cursor = DocumentSpace.allCursorCanvases()
        if !spaces.contains(where: { $0.id == cursor.id }) {
            spaces.append(cursor)
            persistSpaces()
        }
        if needsSetup {
            completeSetup()
        } else {
            refreshLibrary()
        }
        debugLog("addCursorCanvasesSpace spaces=\(spaces.count)")
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
            persistSpaces()
            if needsSetup {
                completeSetup()
            } else {
                refreshLibrary()
            }
        }
    }

    func removeSpace(_ space: DocumentSpace) {
        // Any space is removable, including cursor-all-canvases.
        spaces.removeAll { $0.id == space.id }
        persistSpaces()
        refreshLibrary()
    }

    /// All user-configured spaces (cursor is no longer a special permanent root).
    /// Kept for Settings/UI compatibility; same as `spaces`.
    var extraSpaces: [DocumentSpace] {
        spaces
    }

    /// Reorder any user space among the full spaces list.
    /// - Parameter direction: -1 up, +1 down.
    func moveExtraSpace(id: String, direction: Int) {
        guard let idx = spaces.firstIndex(where: { $0.id == id }) else { return }
        let newIdx = idx + direction
        guard spaces.indices.contains(newIdx) else { return }
        spaces.swapAt(idx, newIdx)
        persistSpaces()
        refreshLibrary()
    }

    func removableSpace(forProject projectName: String) -> DocumentSpace? {
        // Prefer spaceID from any doc in the project (cursor is removable).
        if let spaceID = documents.first(where: { $0.projectName == projectName && !$0.spaceID.isEmpty })?.spaceID,
           let space = spaces.first(where: { $0.id == spaceID }) {
            return space
        }
        // Fallback: match by display name for single-folder spaces.
        return spaces.first { $0.name == projectName }
    }

    func hideProject(_ projectName: String) {
        hiddenProjects.insert(projectName)
        rebuildSidebarProjectNames()
        libraryEpoch &+= 1
        if openDoc?.projectName == projectName {
            selectedID = nil
            if !isDirty { closeDocument() }
        }
        statusMessage = "Hidden “\(projectName)”"
    }

    func unhideProject(_ projectName: String) {
        hiddenProjects.remove(projectName)
        rebuildSidebarProjectNames()
        libraryEpoch &+= 1
        statusMessage = "Showing “\(projectName)”"
    }

    func unhideAllProjects() {
        hiddenProjects.removeAll()
        rebuildSidebarProjectNames()
        libraryEpoch &+= 1
    }

    func excludeFolder(project: String, folderPath: String) {
        guard !folderPath.isEmpty else { return }
        excludedFolders.insert(Self.folderExclusionKey(project: project, folderPath: folderPath))
        rebuildSidebarProjectNames()
        libraryEpoch &+= 1
        statusMessage = "Hidden folder “\(folderPath)”"
    }

    func includeFolder(project: String, folderPath: String) {
        excludedFolders.remove(Self.folderExclusionKey(project: project, folderPath: folderPath))
        libraryEpoch &+= 1
    }

    func clearExcludedFolders() {
        excludedFolders.removeAll()
        libraryEpoch &+= 1
    }

    func moveProject(_ projectName: String, direction: Int) {
        var order = orderedProjectNames
        guard let idx = order.firstIndex(of: projectName) else { return }
        let newIdx = idx + direction
        guard order.indices.contains(newIdx) else { return }
        order.swapAt(idx, newIdx)
        projectOrder = order
        rebuildSidebarProjectNames()
        libraryEpoch &+= 1
    }

    func revealProjectInFinder(_ projectName: String) {
        if let space = removableSpace(forProject: projectName) {
            NSWorkspace.shared.open(space.url)
            return
        }
        if let doc = documents.first(where: { $0.projectName == projectName }) {
            var url = doc.url.deletingLastPathComponent()
            if !doc.folderPath.isEmpty {
                let comps = doc.folderPath.split(separator: "/").count
                for _ in 0..<comps {
                    url = url.deletingLastPathComponent()
                }
            }
            NSWorkspace.shared.open(url)
        }
    }

    func revealFolderInFinder(project: String, folderPath: String) {
        guard let doc = documents.first(where: {
            $0.projectName == project
                && ($0.folderPath == folderPath || $0.folderPath.hasPrefix(folderPath + "/"))
        }) else { return }
        let fileFolder = doc.url.deletingLastPathComponent()
        if doc.folderPath == folderPath {
            NSWorkspace.shared.open(fileFolder)
            return
        }
        if doc.folderPath.hasPrefix(folderPath + "/") {
            let extra = String(doc.folderPath.dropFirst(folderPath.count + 1))
            let up = extra.split(separator: "/").count
            var u = fileFolder
            for _ in 0..<up { u = u.deletingLastPathComponent() }
            NSWorkspace.shared.open(u)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([doc.url])
    }

    // MARK: - Library

    func refreshLibrary() {
        scanGeneration &+= 1
        let generation = scanGeneration
        isScanning = true
        let spacesSnapshot = spaces
        debugLog("refreshLibrary gen=\(generation) spaces=\(spacesSnapshot.map(\.path))")

        // Prefer GCD over Task.detached so results always hop back to main
        // cleanly (detached + @MainActor apply was flaky on first window frame).
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let docs = LibraryScanner().scan(spaces: spacesSnapshot)
            DispatchQueue.main.async {
                guard let self else { return }
                guard generation == self.scanGeneration else {
                    self.debugLog("refreshLibrary ignore stale gen=\(generation) current=\(self.scanGeneration)")
                    return
                }
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

        // Explicit willChange helps sidebar re-render on first populate.
        objectWillChange.send()
        documents = merged
        rebuildSidebarProjectNames()
        isScanning = false
        libraryEpoch &+= 1
        statusMessage = "\(docs.count) documents"
        debugLog("applyLibraryScan scan=\(docs.count) merged=\(merged.count) projects=\(sidebarProjectNames)")

        if let id = selectedID, !merged.contains(where: { $0.id == id }) {
            if isDirty, let open = openDoc {
                // Never wipe an unsaved buffer just because rescan missed the path.
                selectedID = open.id
                if !documents.contains(where: { $0.id == open.id }) {
                    documents.append(open)
                    rebuildSidebarProjectNames()
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

    private func rebuildSidebarProjectNames() {
        let names = Set(
            documents
                .filter { !hiddenProjects.contains($0.projectName) && !isDocumentExcluded($0) }
                .map(\.projectName)
        )
        sidebarProjectNames = orderedNames(from: names)
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
                rebuildSidebarProjectNames()
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
            rebuildSidebarProjectNames()
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
