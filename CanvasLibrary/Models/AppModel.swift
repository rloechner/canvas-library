//
//  AppModel.swift
//  Canvas Library
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
    /// True while a debounced filesystem-driven refresh is pending.
    @Published private(set) var isWatchingLibrary = false

    // MARK: - Open document buffer

    @Published var openDoc: WorkingDocument?
    @Published var bufferText: String = ""
    @Published var originalText: String = ""
    @Published var viewMode: ViewMode = .preview
    @Published var outline: [OutlineNode] = []
    @Published var isDirty: Bool = false
    /// IDs (paths) with unsaved edits — including the open doc and parked buffers.
    @Published private(set) var dirtyDocumentIDs: Set<String> = []
    /// Parked in-memory edits when switching away from a dirty document.
    private var parkedBuffers: [String: ParkedBuffer] = [:]
    /// Preview text editing (canvas): click-to-edit in the live preview.
    @Published var isDesignMode: Bool = false
    @Published private(set) var isExportingPDF = false
    /// Disk changed under a dirty open buffer — user must choose Reload / Keep editing.
    @Published private(set) var externalFileChangePending = false
    /// Line to reveal in the source editor (outline jump); cleared after apply.
    @Published var pendingScrollToLine: Int?

    // MARK: - Canvas / compile

    @Published var isFormatting = false
    @Published var isCompiling = false
    @Published var statusMessage: String?
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
    /// Node + runtime readiness (refreshed on launch / compile errors / settings).
    @Published private(set) var canvasEnvironment = CanvasEnvironmentStatus(
        hasNode: false,
        nodePath: nil,
        hasRuntime: false,
        runtimeSource: .missing,
        isLimitedRuntime: false
    )

    // MARK: - Git (open file + library badges)

    @Published private(set) var gitRootPath: String?
    @Published private(set) var gitBranch: String?
    @Published private(set) var gitFileStatus: GitFileStatus = .unknown
    /// False when git root was found (e.g. real project) but open file is outside that worktree
    /// (common for Cursor `~/.cursor/projects/.../canvases` files).
    @Published private(set) var gitFileInWorktree = false
    @Published private(set) var isGitBusy = false
    @Published var showGitDiffSheet = false
    @Published var showGitCommitSheet = false
    @Published private(set) var gitDiffText = ""
    @Published var gitDiffShowsStaged = false
    @Published var gitCommitMessage = ""
    /// Document path IDs with non-clean git status (for sidebar badges).
    @Published private(set) var gitStatusByDocumentID: [String: GitFileStatus] = [:]
    private var libraryGitGeneration: UInt64 = 0

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
    private let gitService = GitService()
    private let fileWatcher = LibraryFileWatcher()
    private var lastCompileResult: CanvasCompileResult?
    private var gitGeneration: UInt64 = 0
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
    /// Debounce filesystem events before rescanning.
    private var watchDebounceWork: DispatchWorkItem?
    private var pendingWatchPaths: Set<String> = []
    /// Rescan was requested while design-mode / compile held the watcher — run after idle.
    private var deferredWatchRescan = false
    /// mtime/size of open file at last load/save (external-change detection).
    private var openFileDiskStamp: DiskStamp?
    /// Ignore watcher/reload races immediately after our own save.
    private var ignoreDiskChangesUntil: Date = .distantPast
    private var appActivationObserver: NSObjectProtocol?

    private struct DiskStamp: Equatable {
        var modifiedAt: Date
        var fileSize: Int64
    }

    /// True while the user is mid-edit in the live preview — must not thrash library/preview.
    private var shouldHoldLibraryWatcher: Bool {
        isDesignMode || isCompiling
    }

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
        configureFileWatcher()
        refreshCanvasEnvironment()
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.checkOpenDocumentExternalChange(reason: "app-active")
            }
        }
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
        restartLibraryWatcher()
    }

    // MARK: - Filesystem watcher

    private func configureFileWatcher() {
        fileWatcher.onPathsChanged = { [weak self] paths in
            DispatchQueue.main.async {
                self?.handleFilesystemEvents(paths)
            }
        }
        restartLibraryWatcher()
    }

    private func restartLibraryWatcher() {
        let urls = spaces.map(\.url)
        fileWatcher.setRoots(urls)
        isWatchingLibrary = !urls.isEmpty
    }

    private func handleFilesystemEvents(_ paths: [String]) {
        guard !spaces.isEmpty else { return }

        let normalized = paths.map { Self.standardizedPath($0) }

        // Our own atomic saves briefly touch the open file — skip thrash.
        if Date() < ignoreDiskChangesUntil {
            if let openPath = openDoc.map({ Self.standardizedPath($0.urlPath) }) {
                let onlyOpen = normalized.allSatisfy { path in
                    path == openPath
                }
                if onlyOpen {
                    // Stamp only — do not rescan the whole library after our save.
                    captureOpenFileDiskStamp(for: URL(fileURLWithPath: openPath))
                    return
                }
            }
        }

        // Exact open-file path only (not parent dirs — those fire constantly).
        if let open = openDoc {
            let openPath = Self.standardizedPath(open.urlPath)
            if normalized.contains(openPath) {
                checkOpenDocumentExternalChange(reason: "watch")
            }
        }

        // Ignore noise that cannot change the library document set.
        let relevant = normalized.filter { Self.isWatchEventRelevant($0) }
        guard !relevant.isEmpty else { return }

        for path in relevant {
            pendingWatchPaths.insert(path)
        }

        // Design-mode + compile rewrites the live preview; library rescans steal focus,
        // clobber status, and make Save impossible. Defer until the user finishes.
        if shouldHoldLibraryWatcher {
            deferredWatchRescan = true
            return
        }

        scheduleWatchRescanFlush()
    }

    private func scheduleWatchRescanFlush() {
        watchDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flushPendingWatchRescan()
        }
        watchDebounceWork = work
        // Longer debounce: Cursor project trees are chatty.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: work)
    }

    /// Call when design mode / compile finishes so deferred FS events can apply.
    private func flushDeferredWatchRescanIfNeeded() {
        guard deferredWatchRescan || !pendingWatchPaths.isEmpty else { return }
        guard !shouldHoldLibraryWatcher else { return }
        deferredWatchRescan = false
        scheduleWatchRescanFlush()
    }

    private func flushPendingWatchRescan() {
        // Still editing in preview — hold again.
        if shouldHoldLibraryWatcher {
            deferredWatchRescan = true
            return
        }

        let paths = Array(pendingWatchPaths)
        pendingWatchPaths.removeAll()
        deferredWatchRescan = false
        guard !paths.isEmpty else { return }

        let affected = LibraryScanner.spacesAffected(by: paths, in: spaces)
        // Silent when the user has unsaved work so we don't replace “Unsaved changes”.
        let status: String? = isDirty ? nil : "Library updated"
        if affected.isEmpty {
            // Paths didn't map (symlink /private prefix). Full rescan as recovery only.
            refreshLibrary(status: status)
            return
        }
        if affected.count == spaces.count {
            refreshLibrary(status: status)
            return
        }
        refreshLibrary(spaces: affected, status: status)
    }

    /// Paths that can add/remove/update library rows (or their parent folders).
    private static func isWatchEventRelevant(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if name == ".DS_Store" || name == ".git" || name.hasPrefix("._") { return false }
        if name == "node_modules" || name == "DerivedData" || name == ".build" { return false }
        // Directory events: keep (new/renamed folders may contain docs).
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return true
        }
        // File deleted (path may no longer exist) — still relevant if it looked like a doc.
        return LibraryScanner.isLibraryDocumentPath(path)
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
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
        persistSpaces() // also restarts watcher
        defaults.set(true, forKey: didCompleteSetupKey)
        needsSetup = false
        documents = []
        rebuildSidebarProjectNames()
        libraryEpoch &+= 1
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

    func refreshLibrary(status: String? = nil) {
        refreshLibrary(spaces: spaces, status: status)
    }

    /// Full or partial library scan. Pass a subset of spaces for incremental refresh.
    func refreshLibrary(spaces scanSpaces: [DocumentSpace], status: String?) {
        scanGeneration &+= 1
        let generation = scanGeneration
        isScanning = true
        let spacesSnapshot = scanSpaces
        let isPartial = scanSpaces.count < spaces.count && !scanSpaces.isEmpty
        debugLog("refreshLibrary gen=\(generation) partial=\(isPartial) spaces=\(spacesSnapshot.map(\.path))")

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
                if isPartial {
                    self.applyPartialLibraryScan(docs, scannedSpaces: spacesSnapshot, status: status)
                } else {
                    self.applyLibraryScan(docs, status: status)
                }
            }
        }
    }

    private func applyLibraryScan(_ docs: [WorkingDocument], status: String? = nil) {
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
        // Don't clobber “Unsaved changes” / design-mode status with scan chatter.
        if let status {
            statusMessage = status
        } else if !isDirty && !isDesignMode {
            statusMessage = "\(docs.count) documents"
        }
        debugLog("applyLibraryScan scan=\(docs.count) merged=\(merged.count) projects=\(sidebarProjectNames)")

        reconcileSelectionAfterScan(merged: merged)
        ensureExpandedProjectsAfterScan()
        if !isDesignMode {
            refreshLibraryGitStatuses()
            checkOpenDocumentExternalChange(reason: "scan")
        }
    }

    /// Merge a partial space rescan into the existing library set.
    private func applyPartialLibraryScan(
        _ docs: [WorkingDocument],
        scannedSpaces: [DocumentSpace],
        status: String?
    ) {
        let scannedIDs = Set(scannedSpaces.map(\.id))
        var byPath: [String: WorkingDocument] = [:]
        for doc in documents where !scannedIDs.contains(doc.spaceID) {
            byPath[doc.urlPath] = doc
        }
        for doc in docs {
            byPath[doc.urlPath] = doc
        }
        // Keep open file outside scanned spaces.
        if let open = openDoc {
            byPath[open.urlPath] = byPath[open.urlPath] ?? open
        }
        let merged = LibraryScanner.sortedDocuments(Array(byPath.values))
        objectWillChange.send()
        documents = merged
        rebuildSidebarProjectNames()
        isScanning = false
        libraryEpoch &+= 1
        if let status {
            statusMessage = status
        } else if !isDirty && !isDesignMode {
            statusMessage = "\(merged.count) documents"
        }
        debugLog("applyPartialLibraryScan new=\(docs.count) merged=\(merged.count)")

        reconcileSelectionAfterScan(merged: merged)
        ensureExpandedProjectsAfterScan()
        if !isDesignMode {
            refreshLibraryGitStatuses()
            checkOpenDocumentExternalChange(reason: "partial-scan")
        }
    }

    private func reconcileSelectionAfterScan(merged: [WorkingDocument]) {
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
        // Park unsaved work — do not discard. Sidebar shows a dirty dot.
        parkCurrentDocument()
        selectedID = doc.id
        expandAncestors(of: doc)
        open(doc)
    }

    /// Whether a library row should show an unsaved alert dot.
    func hasUnsavedEdits(forDocumentID id: String) -> Bool {
        dirtyDocumentIDs.contains(id)
    }

    /// Git status for a library row (if known and non-clean).
    func gitStatus(forDocumentID id: String) -> GitFileStatus? {
        if let open = openDoc, open.id == id, gitFileStatus.isChanged {
            return gitFileStatus
        }
        guard let status = gitStatusByDocumentID[id], status.isChanged else { return nil }
        return status
    }

    private struct ParkedBuffer {
        var text: String
        var originalText: String
        var viewMode: ViewMode
        var isDesignMode: Bool
    }

    /// Stash the open buffer so the user can switch away and return to edits.
    private func parkCurrentDocument() {
        guard let doc = openDoc else { return }
        if isDirty {
            parkedBuffers[doc.id] = ParkedBuffer(
                text: bufferText,
                originalText: originalText,
                viewMode: viewMode,
                isDesignMode: isDesignMode
            )
        } else {
            parkedBuffers.removeValue(forKey: doc.id)
        }
        recomputeDirtyIDs()
    }

    private func recomputeDirtyIDs() {
        var ids = Set(parkedBuffers.keys.filter { parkedBuffers[$0]?.text != parkedBuffers[$0]?.originalText })
        if let open = openDoc, isDirty {
            ids.insert(open.id)
        }
        dirtyDocumentIDs = ids
    }

    /// Save / Discard / Cancel when an action requires a clean buffer (e.g. git stage).
    @discardableResult
    func confirmNavigateAwayIfDirty() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Unsaved changes"
        alert.informativeText = "Save changes before continuing?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveDocument()
            return !isDirty
        case .alertSecondButtonReturn:
            if let id = openDoc?.id {
                parkedBuffers.removeValue(forKey: id)
            }
            bufferText = originalText
            isDirty = false
            recomputeDirtyIDs()
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
            // Restore parked edits if any; otherwise load from disk.
            let parked = parkedBuffers[doc.id]
            let diskText = try String(contentsOf: doc.url, encoding: .utf8)
            let text = parked?.text ?? diskText
            let original = parked?.originalText ?? diskText

            openDoc = doc
            bufferText = text
            originalText = original
            isDirty = text != original
            isDesignMode = parked?.isDesignMode ?? false
            outline = outlineParser.parse(text)
            canvasError = nil
            externalFileChangePending = false
            pendingScrollToLine = nil
            viewMode = parked?.viewMode ?? .preview
            captureOpenFileDiskStamp(for: doc.url)
            pushRecent(doc.id)
            // Surface externally opened files in the sidebar without a full rescan.
            if !documents.contains(where: { $0.id == doc.id }) {
                documents.append(doc)
                rebuildSidebarProjectNames()
                libraryEpoch &+= 1
            }
            recomputeDirtyIDs()

            clearGitState()
            switch doc.kind {
            case .canvas:
                compileCanvas(force: true)
                statusMessage = isDirty
                    ? "Restored unsaved edits · \(doc.displayTitle)"
                    : "Opened canvas · \(doc.displayTitle)"
            case .markdown:
                clearCanvasHost()
                markdownReloadToken = UUID()
                statusMessage = isDirty
                    ? "Restored unsaved edits · \(doc.displayTitle)"
                    : "Opened markdown · \(doc.displayTitle)"
            }
            if isDesignMode, doc.kind == .canvas {
                viewMode = .preview
            }
            refreshGitState()
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
        parkCurrentDocument()
        openDoc = nil
        bufferText = ""
        originalText = ""
        isDirty = false
        isDesignMode = false
        outline = []
        externalFileChangePending = false
        openFileDiskStamp = nil
        pendingScrollToLine = nil
        clearCanvasHost()
        clearGitState()
        recomputeDirtyIDs()
    }

    /// Enable click-to-edit on the live canvas preview (writes through to source).
    func setDesignMode(_ on: Bool) {
        guard openDoc?.kind == .canvas else {
            isDesignMode = false
            flushDeferredWatchRescanIfNeeded()
            return
        }
        isDesignMode = on
        if on {
            viewMode = .preview
            // Cancel any pending library rescan so unlock-edit isn't fighting FSEvents.
            watchDebounceWork?.cancel()
            statusMessage = "Click text in the preview to edit · Save when ready"
        } else {
            statusMessage = isDirty ? "Unsaved changes" : "Preview editing off"
            // Do NOT recompile when leaving design mode — a full WebView reload jumps
            // scroll to the top. DOM already matches the buffer for successful edits.
            flushDeferredWatchRescanIfNeeded()
        }
    }

    /// Apply a text edit that originated from unlocked preview.
    func applyPreviewTextEdit(oldText: String, newText: String) {
        guard openDoc?.kind == .canvas else { return }
        let result = SourceTextRewriter.replace(oldText: oldText, with: newText, in: bufferText)
        if result.replaced {
            updateBuffer(result.text)
            // Keep the live DOM as-is (user already sees the edit). Recompiling here
            // reloads the WebView and jumps scroll to the top — only recompile on
            // explicit Reload Preview / open / source-driven changes.
            let multi = result.occurrenceCount > 1 ? " (first of \(result.occurrenceCount) matches)" : ""
            statusMessage = "Preview edit → source · Save when ready\(multi)"
        } else {
            statusMessage = "Couldn't map “\(String(oldText.prefix(40)))” to source — edit in Source"
        }
    }

    func updateBuffer(_ newText: String) {
        guard bufferText != newText else { return }
        bufferText = newText
        isDirty = bufferText != originalText
        if openDoc?.kind == .canvas {
            outline = outlineParser.parse(newText)
        }
        // Keep parked snapshot in sync if we re-park later.
        if let id = openDoc?.id, isDirty {
            parkedBuffers[id] = ParkedBuffer(
                text: bufferText,
                originalText: originalText,
                viewMode: viewMode,
                isDesignMode: isDesignMode
            )
        } else if let id = openDoc?.id {
            parkedBuffers.removeValue(forKey: id)
        }
        recomputeDirtyIDs()
        if isDirty {
            statusMessage = "Unsaved changes"
        }
    }

    /// Discard buffer edits and restore last loaded/saved text.
    /// (Does not touch git — use `discardGitChanges()` to restore the last commit.)
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
        if let id = openDoc?.id {
            parkedBuffers.removeValue(forKey: id)
        }
        recomputeDirtyIDs()
        if openDoc?.kind == .canvas {
            outline = outlineParser.parse(originalText)
        } else {
            markdownReloadToken = UUID()
        }
        // Bump identity so Monaco reloads content even if string equal-check races
        editorReloadNonce = UUID()
        statusMessage = "Reverted unsaved changes"
    }

    // MARK: - Save / format

    func saveDocument() {
        guard let doc = openDoc else { return }
        do {
            ignoreDiskChangesUntil = Date().addingTimeInterval(1.2)
            try bufferText.write(to: doc.url, atomically: true, encoding: .utf8)
            originalText = bufferText
            isDirty = false
            parkedBuffers.removeValue(forKey: doc.id)
            recomputeDirtyIDs()
            externalFileChangePending = false
            captureOpenFileDiskStamp(for: doc.url)
            // Leave unlock-preview editing — back to normal preview after a successful save.
            if isDesignMode {
                setDesignMode(false)
            }
            statusMessage = "Saved"
            // In-place metadata update — avoid full rescan (sidebar thrash + close races).
            touchOpenDocumentMetadata()
            refreshGitState()
            // Sidebar M/U badges update after disk write.
            refreshLibraryGitStatuses()
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - External file change

    private func captureOpenFileDiskStamp(for url: URL) {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        openFileDiskStamp = DiskStamp(
            modifiedAt: values?.contentModificationDate ?? .distantPast,
            fileSize: Int64(values?.fileSize ?? 0)
        )
    }

    private func currentDiskStamp(for url: URL) -> DiskStamp? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return DiskStamp(
            modifiedAt: values?.contentModificationDate ?? .distantPast,
            fileSize: Int64(values?.fileSize ?? 0)
        )
    }

    /// Compare open file mtime/size to the stamp from last open/save/reload.
    func checkOpenDocumentExternalChange(reason: String) {
        guard let doc = openDoc else {
            externalFileChangePending = false
            return
        }
        if Date() < ignoreDiskChangesUntil { return }
        // Never yank the buffer/preview while unlock-editing — that made Save impossible.
        if isDesignMode {
            return
        }
        guard let disk = currentDiskStamp(for: doc.url) else {
            // File deleted under us — keep buffer; banner via status only.
            if !isDirty {
                statusMessage = "File missing on disk · \(doc.fileName)"
            }
            return
        }
        guard let stamp = openFileDiskStamp else {
            openFileDiskStamp = disk
            return
        }
        guard disk != stamp else {
            if externalFileChangePending { externalFileChangePending = false }
            return
        }

        debugLog("external change reason=\(reason) file=\(doc.fileName)")
        if isDirty {
            externalFileChangePending = true
            statusMessage = "File changed on disk — reload or keep editing"
            return
        }

        // Clean buffer: auto-reload from disk.
        do {
            let text = try String(contentsOf: doc.url, encoding: .utf8)
            bufferText = text
            originalText = text
            isDirty = false
            outline = outlineParser.parse(text)
            openFileDiskStamp = disk
            externalFileChangePending = false
            editorReloadNonce = UUID()
            touchOpenDocumentMetadata()
            switch doc.kind {
            case .canvas: compileCanvas(force: true)
            case .markdown: markdownReloadToken = UUID()
            }
            statusMessage = "Reloaded from disk · \(doc.displayTitle)"
            refreshGitState()
        } catch {
            statusMessage = "Disk changed but reload failed: \(error.localizedDescription)"
            externalFileChangePending = true
        }
    }

    /// Reload open file from disk, discarding buffer edits.
    func reloadOpenDocumentFromDisk() {
        guard let doc = openDoc else { return }
        do {
            let text = try String(contentsOf: doc.url, encoding: .utf8)
            bufferText = text
            originalText = text
            isDirty = false
            parkedBuffers.removeValue(forKey: doc.id)
            recomputeDirtyIDs()
            outline = outlineParser.parse(text)
            captureOpenFileDiskStamp(for: doc.url)
            externalFileChangePending = false
            editorReloadNonce = UUID()
            touchOpenDocumentMetadata()
            switch doc.kind {
            case .canvas: compileCanvas(force: true)
            case .markdown: markdownReloadToken = UUID()
            }
            statusMessage = "Reloaded from disk"
            refreshGitState()
        } catch {
            statusMessage = "Reload failed: \(error.localizedDescription)"
            NSAlert(error: error).runModal()
        }
    }

    /// Keep editing the buffer; update stamp so we don't re-prompt until next disk change.
    func dismissExternalFileChange() {
        if let doc = openDoc {
            captureOpenFileDiskStamp(for: doc.url)
        }
        externalFileChangePending = false
        statusMessage = "Keeping your edits (disk version ignored until next change)"
    }

    func refreshCanvasEnvironment() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = CanvasEnvironment.probe()
            DispatchQueue.main.async {
                self?.canvasEnvironment = status
            }
        }
    }

    /// Export the current document to a PDF chosen by the user.
    func exportPDF() {
        guard let doc = openDoc else { return }
        if !confirmProceedIfDirty(action: "export") { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = sanitizedFileBaseName(doc.displayTitle) + ".pdf"
        panel.canCreateDirectories = true
        panel.title = "Export PDF"
        panel.message = "Save a PDF of the current document preview (or source fallback)."
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        isExportingPDF = true
        statusMessage = "Exporting PDF…"
        let title = doc.displayTitle

        Task { @MainActor in
            defer { self.isExportingPDF = false }
            do {
                let data = try await renderCurrentDocumentPDF()
                try data.write(to: dest, options: .atomic)
                self.statusMessage = "Exported PDF · \(dest.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([dest])
            } catch {
                self.statusMessage = "PDF export failed: \(error.localizedDescription)"
                NSAlert(error: error).runModal()
            }
        }
    }

    /// Print the current document (renders the same PDF pipeline, then system print panel).
    func printDocument() {
        guard openDoc != nil else { return }
        if !confirmProceedIfDirty(action: "print") { return }

        isExportingPDF = true
        statusMessage = "Preparing print…"
        let title = openDoc?.displayTitle ?? "Document"

        Task { @MainActor in
            defer { self.isExportingPDF = false }
            do {
                let data = try await renderCurrentDocumentPDF()
                try PDFExporter.presentPrintPanel(for: data, jobTitle: title)
                self.statusMessage = "Print dialog closed"
            } catch {
                self.statusMessage = "Print failed: \(error.localizedDescription)"
                NSAlert(error: error).runModal()
            }
        }
    }

    /// Shared PDF render path for export + print.
    private func renderCurrentDocumentPDF() async throws -> Data {
        guard let doc = openDoc else { throw PDFExporterError.noContent }
        let kind = doc.kind
        let text = bufferText
        let title = doc.displayTitle
        let hostURL = canvasHostURL
        let workDir = canvasWorkDirectory

        switch kind {
        case .markdown:
            return try await PDFExporter.exportMarkdown(text, title: title)
        case .canvas:
            if let hostURL, let workDir {
                do {
                    return try await PDFExporter.pdfData(
                        fromFileURL: hostURL,
                        allowingReadAccessTo: workDir,
                        settle: 1.0
                    )
                } catch {
                    return try await PDFExporter.exportSource(text, title: title)
                }
            }
            return try await PDFExporter.exportSource(text, title: title)
        }
    }

    /// Ask to save when dirty before export/print. Returns false if the user cancelled.
    private func confirmProceedIfDirty(action: String) -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save before \(action)?"
        alert.informativeText = "Unsaved edits are included from the editor buffer. Save to disk first if you want the file and export to match."
        alert.addButton(withTitle: "Save & Continue")
        alert.addButton(withTitle: "Continue with Buffer")
        alert.addButton(withTitle: "Cancel")
        let r = alert.runModal()
        if r == .alertThirdButtonReturn { return false }
        if r == .alertFirstButtonReturn {
            saveDocument()
            if isDirty { return false }
        }
        return true
    }

    private func sanitizedFileBaseName(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Document" : cleaned
    }

    // MARK: - Git

    var isInGitRepo: Bool { gitRootPath != nil }

    var gitFileStatusLabel: String? { gitFileStatus.capsuleTitle }

    var canStageCurrentFile: Bool {
        guard isInGitRepo, gitFileInWorktree, openDoc != nil, !isGitBusy else { return false }
        return gitFileStatus.hasWorkTreeChanges || gitFileStatus.isUntracked
    }

    var canUnstageCurrentFile: Bool {
        guard isInGitRepo, gitFileInWorktree, openDoc != nil, !isGitBusy else { return false }
        return gitFileStatus.isStaged
    }

    var canCommitCurrentFile: Bool {
        guard isInGitRepo, gitFileInWorktree, openDoc != nil, !isGitBusy else { return false }
        return gitFileStatus.isStaged || gitFileStatus.hasWorkTreeChanges || gitFileStatus.isUntracked
    }

    /// True when the open file can be restored to the last commit (after save, still modified).
    var canDiscardGitChanges: Bool {
        guard isInGitRepo, gitFileInWorktree, openDoc != nil, !isGitBusy else { return false }
        return gitFileStatus.canDiscardToHEAD
    }

    private func clearGitState() {
        gitGeneration &+= 1
        gitRootPath = nil
        gitBranch = nil
        gitFileStatus = .unknown
        gitFileInWorktree = false
        isGitBusy = false
        gitDiffText = ""
        gitCommitMessage = ""
        showGitDiffSheet = false
        showGitCommitSheet = false
    }

    /// Refresh branch + porcelain status for the open file.
    func refreshGitState() {
        guard let doc = openDoc else {
            clearGitState()
            return
        }
        gitGeneration &+= 1
        let generation = gitGeneration
        let fileURL = doc.url
        let docID = doc.id
        isGitBusy = true

        Task.detached(priority: .utility) { [gitService] in
            let root = gitService.findGitRoot(startingAt: fileURL)
            var branch: String?
            var status: GitFileStatus = .unknown
            var inTree = false
            if let root {
                branch = gitService.currentBranch(repoRoot: root)
                if let rel = gitService.relativePath(fileURL: fileURL, repoRoot: root) {
                    inTree = true
                    status = gitService.fileStatus(repoRoot: root, pathRelativeToRoot: rel)
                } else {
                    // e.g. Cursor cache file linked to a real project repo
                    inTree = false
                    status = .unknown
                }
            }
            await MainActor.run {
                guard generation == self.gitGeneration, self.openDoc?.url.path == fileURL.path else { return }
                self.isGitBusy = false
                if let root {
                    self.gitRootPath = root.path
                    self.gitBranch = branch
                    self.gitFileStatus = status
                    self.gitFileInWorktree = inTree
                    self.mergeOpenFileStatusIntoLibraryMap(documentID: docID, status: status)
                    if !inTree, let msg = self.statusMessage, msg.hasPrefix("Opened") || msg.hasPrefix("Restored") {
                        if !msg.contains("worktree") {
                            self.statusMessage = msg + " · git: \(branch ?? "repo") (file outside worktree)"
                        }
                    }
                } else {
                    self.gitRootPath = nil
                    self.gitBranch = nil
                    self.gitFileStatus = .unknown
                    self.gitFileInWorktree = false
                    self.gitStatusByDocumentID.removeValue(forKey: docID)
                    if let msg = self.statusMessage, (msg.hasPrefix("Opened") || msg.hasPrefix("Restored")), !msg.contains("git") {
                        self.statusMessage = msg + " · not a git repository"
                    }
                }
            }
        }
    }

    private func mergeOpenFileStatusIntoLibraryMap(documentID: String, status: GitFileStatus) {
        var map = gitStatusByDocumentID
        if status.isChanged {
            map[documentID] = status
        } else {
            map.removeValue(forKey: documentID)
        }
        gitStatusByDocumentID = map
    }

    /// Scan all library documents for git porcelain status (sidebar badges).
    func refreshLibraryGitStatuses() {
        libraryGitGeneration &+= 1
        let generation = libraryGitGeneration
        let docs = documents
        guard !docs.isEmpty else {
            gitStatusByDocumentID = [:]
            return
        }

        Task.detached(priority: .utility) { [gitService] in
            // Group docs by discovered git root so we run porcelain once per repo.
            var rootCache: [String: URL?] = [:]
            var relByDocID: [String: (rootPath: String, rel: String)] = [:]

            for doc in docs {
                let dir = doc.url.deletingLastPathComponent().path
                let root: URL?
                if let cached = rootCache[dir] {
                    root = cached
                } else {
                    let found = gitService.findGitRoot(startingAt: doc.url)
                    rootCache[dir] = found
                    root = found
                }
                guard let root,
                      let rel = gitService.relativePath(fileURL: doc.url, repoRoot: root)
                else { continue }
                relByDocID[doc.id] = (root.path, rel)
            }

            let uniqueRoots = Set(relByDocID.values.map(\.rootPath))
            var statusByRootRel: [String: [String: GitFileStatus]] = [:]
            for rootPath in uniqueRoots {
                let root = URL(fileURLWithPath: rootPath)
                statusByRootRel[rootPath] = gitService.statusMap(repoRoot: root)
            }

            var result: [String: GitFileStatus] = [:]
            for (docID, pair) in relByDocID {
                if let status = statusByRootRel[pair.rootPath]?[pair.rel], status.isChanged {
                    result[docID] = status
                }
            }

            await MainActor.run {
                guard generation == self.libraryGitGeneration else { return }
                // Prefer live open-file status if fresher.
                if let open = self.openDoc, self.gitFileStatus.isChanged {
                    result[open.id] = self.gitFileStatus
                } else if let open = self.openDoc, !self.gitFileStatus.isChanged {
                    result.removeValue(forKey: open.id)
                }
                self.gitStatusByDocumentID = result
            }
        }
    }

    /// Save if dirty before stage/commit. Returns false if user cancels or save fails.
    @discardableResult
    func prepareGitMutation() -> Bool {
        guard openDoc != nil else { return false }
        if isDirty {
            let alert = NSAlert()
            alert.messageText = "Save before git?"
            alert.informativeText = "Unsaved edits must be written to disk before staging or committing."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            saveDocument()
            if isDirty { return false }
        }
        return true
    }

    func stageCurrentFile() {
        guard prepareGitMutation(), let doc = openDoc, let rootPath = gitRootPath else { return }
        let root = URL(fileURLWithPath: rootPath)
        guard let rel = gitService.relativePath(fileURL: doc.url, repoRoot: root) else {
            statusMessage = "File is outside the git repository"
            return
        }
        gitGeneration &+= 1
        let generation = gitGeneration
        isGitBusy = true
        Task.detached(priority: .userInitiated) { [gitService] in
            do {
                try gitService.stage(repoRoot: root, pathRelativeToRoot: rel)
                await MainActor.run {
                    guard generation == self.gitGeneration else { return }
                    self.isGitBusy = false
                    self.statusMessage = "Staged · \(doc.fileName)"
                    self.refreshGitState()
                    self.refreshLibraryGitStatuses()
                }
            } catch {
                await MainActor.run {
                    guard generation == self.gitGeneration else { return }
                    self.isGitBusy = false
                    self.statusMessage = "Stage failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func unstageCurrentFile() {
        guard let doc = openDoc, let rootPath = gitRootPath else { return }
        let root = URL(fileURLWithPath: rootPath)
        guard let rel = gitService.relativePath(fileURL: doc.url, repoRoot: root) else { return }
        gitGeneration &+= 1
        let generation = gitGeneration
        isGitBusy = true
        Task.detached(priority: .userInitiated) { [gitService] in
            do {
                try gitService.unstage(repoRoot: root, pathRelativeToRoot: rel)
                await MainActor.run {
                    guard generation == self.gitGeneration else { return }
                    self.isGitBusy = false
                    self.statusMessage = "Unstaged · \(doc.fileName)"
                    self.refreshGitState()
                    self.refreshLibraryGitStatuses()
                }
            } catch {
                await MainActor.run {
                    guard generation == self.gitGeneration else { return }
                    self.isGitBusy = false
                    self.statusMessage = "Unstage failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Restore the open file to HEAD (index + worktree), then reload the buffer.
    /// Use after save when the file is still modified relative to the last commit.
    func discardGitChanges() {
        guard let doc = openDoc, let rootPath = gitRootPath else { return }
        guard isInGitRepo, gitFileInWorktree, !isGitBusy else { return }
        if gitFileStatus.isUntracked {
            statusMessage = "Untracked file — discard isn’t available (delete in Finder if needed)"
            return
        }
        guard gitFileStatus.canDiscardToHEAD else { return }
        let root = URL(fileURLWithPath: rootPath)
        guard let rel = gitService.relativePath(fileURL: doc.url, repoRoot: root) else { return }

        let alert = NSAlert()
        alert.messageText = "Discard changes to “\(doc.fileName)”?"
        alert.informativeText = isDirty
            ? "Unsaved edits and all uncommitted changes will be permanently discarded. The file will match the last commit."
            : "All uncommitted changes (staged and unstaged) will be permanently discarded. The file will match the last commit."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        gitGeneration &+= 1
        let generation = gitGeneration
        isGitBusy = true
        Task.detached(priority: .userInitiated) { [gitService] in
            do {
                try gitService.discardToHEAD(repoRoot: root, pathRelativeToRoot: rel)
                let diskText = try String(contentsOf: doc.url, encoding: .utf8)
                await MainActor.run {
                    guard generation == self.gitGeneration, self.openDoc?.id == doc.id else { return }
                    self.isGitBusy = false
                    self.parkedBuffers.removeValue(forKey: doc.id)
                    self.bufferText = diskText
                    self.originalText = diskText
                    self.isDirty = false
                    self.recomputeDirtyIDs()
                    self.editorReloadNonce = UUID()
                    if doc.kind == .canvas {
                        self.outline = self.outlineParser.parse(diskText)
                        self.compileCanvas(force: true)
                    } else {
                        self.markdownReloadToken = UUID()
                    }
                    self.touchOpenDocumentMetadata()
                    self.statusMessage = "Discarded changes · \(doc.fileName)"
                    self.refreshGitState()
                    self.refreshLibraryGitStatuses()
                }
            } catch {
                await MainActor.run {
                    guard generation == self.gitGeneration else { return }
                    self.isGitBusy = false
                    self.statusMessage = "Discard failed: \(error.localizedDescription)"
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    func presentGitDiff() {
        guard openDoc != nil else { return }
        gitDiffShowsStaged = false
        loadGitDiff()
        showGitDiffSheet = true
    }

    func loadGitDiff() {
        guard let doc = openDoc, let rootPath = gitRootPath else {
            gitDiffText = ""
            return
        }
        let root = URL(fileURLWithPath: rootPath)
        guard let rel = gitService.relativePath(fileURL: doc.url, repoRoot: root) else {
            gitDiffText = ""
            return
        }
        let staged = gitDiffShowsStaged
        let status = gitFileStatus
        gitGeneration &+= 1
        let generation = gitGeneration
        isGitBusy = true
        Task.detached(priority: .userInitiated) { [gitService] in
            do {
                var text = try gitService.diff(repoRoot: root, pathRelativeToRoot: rel, staged: staged)
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !staged, status.isUntracked {
                        text = "Untracked file — stage it to start tracking.\nNo work-tree diff until the file is in the index."
                    } else if staged, !status.isStaged {
                        text = "Nothing staged for this file."
                    } else {
                        text = "No changes."
                    }
                }
                await MainActor.run {
                    guard generation == self.gitGeneration else { return }
                    self.isGitBusy = false
                    self.gitDiffText = text
                }
            } catch {
                await MainActor.run {
                    guard generation == self.gitGeneration else { return }
                    self.isGitBusy = false
                    self.gitDiffText = "Could not load diff:\n\(error.localizedDescription)"
                }
            }
        }
    }

    func presentGitCommit() {
        guard prepareGitMutation() else { return }
        refreshGitState()
        // Allow sheet open even if not staged yet — commit action will stage if needed after re-check
        showGitCommitSheet = true
    }

    func commitCurrentFile() {
        let message = gitCommitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            statusMessage = "Enter a commit message"
            return
        }
        guard prepareGitMutation(), let doc = openDoc, let rootPath = gitRootPath else { return }
        let root = URL(fileURLWithPath: rootPath)
        guard let rel = gitService.relativePath(fileURL: doc.url, repoRoot: root) else { return }

        gitGeneration &+= 1
        let generation = gitGeneration
        isGitBusy = true
        let needsStage = !gitFileStatus.isStaged && (gitFileStatus.hasWorkTreeChanges || gitFileStatus.isUntracked)

        Task.detached(priority: .userInitiated) { [gitService] in
            do {
                if needsStage {
                    try gitService.stage(repoRoot: root, pathRelativeToRoot: rel)
                }
                // Re-check: commit requires index changes
                let status = gitService.fileStatus(repoRoot: root, pathRelativeToRoot: rel)
                guard status.isStaged else {
                    await MainActor.run {
                        guard generation == self.gitGeneration else { return }
                        self.isGitBusy = false
                        self.statusMessage = "Nothing to commit for this file"
                    }
                    return
                }
                try gitService.commit(repoRoot: root, message: message)
                await MainActor.run {
                    guard generation == self.gitGeneration else { return }
                    self.isGitBusy = false
                    self.gitCommitMessage = ""
                    self.showGitCommitSheet = false
                    self.statusMessage = "Committed · \(doc.fileName)"
                    self.refreshGitState()
                    self.refreshLibraryGitStatuses()
                }
            } catch {
                await MainActor.run {
                    guard generation == self.gitGeneration else { return }
                    self.isGitBusy = false
                    self.statusMessage = "Commit failed: \(error.localizedDescription)"
                }
            }
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
            // Explicit user action — allowed even during design mode.
            compileCanvas(force: true)
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
        // Bump even for the same line so Monaco re-reveals.
        pendingScrollToLine = nil
        DispatchQueue.main.async { [weak self] in
            self?.pendingScrollToLine = max(1, node.line)
        }
        statusMessage = "Outline · \(node.name) · L\(node.line)"
    }

    // MARK: - Canvas compile

    /// - Parameter force: When true, compile even during design mode (manual Reload / open).
    ///   Default false so unlock-preview edits never tear down the live WebView.
    func compileCanvas(force: Bool = false) {
        guard openDoc?.kind == .canvas else { return }
        // Design-mode edits already live in the DOM + buffer. A recompile reloads the
        // host page and jumps scroll to the top — never do that unless explicitly forced.
        if isDesignMode && !force {
            debugLog("compileCanvas skipped — design mode active (force=false)")
            return
        }
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
                    self.statusMessage = self.isDirty
                        ? "Compile failed · unsaved edits kept"
                        : "Compile failed"
                    self.refreshCanvasEnvironment()
                    // Stay in preview if unlock-editing so we don't yank the user to Source.
                    if !self.isDesignMode {
                        self.viewMode = .source
                    }
                    self.flushDeferredWatchRescanIfNeeded()
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
        if isDirty || isDesignMode {
            statusMessage = isDesignMode
                ? "Preview updated · unsaved edits — Save when ready"
                : "Preview updated · unsaved changes"
        } else if canvasEnvironment.isLimitedRuntime {
            statusMessage = "Canvas ready · minimal host"
        } else {
            statusMessage = "Canvas ready"
        }
        if viewMode != .source {
            viewMode = .preview
        }
        // Compile held the library watcher; apply any deferred FSEvents now.
        flushDeferredWatchRescanIfNeeded()
        // Keep readiness badge honest after a successful resolve.
        refreshCanvasEnvironment()
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
            statusMessage = "Editing in preview — click text, then Save"
        } else if isDirty {
            statusMessage = "Canvas rendered · unsaved changes"
        } else {
            statusMessage = "Canvas rendered"
        }
    }

    func canvasDidFail(_ message: String) {
        canvasError = message
        statusMessage = isDirty ? "Canvas error · unsaved edits kept" : "Canvas error"
        isCompiling = false
        flushDeferredWatchRescanIfNeeded()
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
        recentIDs.compactMap { id in
            if let doc = documents.first(where: { $0.id == id }) { return doc }
            // Fall back to a lightweight stub so Recents still works after hide/filter.
            let url = URL(fileURLWithPath: id)
            guard FileManager.default.fileExists(atPath: id) else { return nil }
            let name = url.lastPathComponent.lowercased()
            let kind: DocumentKind =
                (name.hasSuffix(".canvas.tsx") || name.hasSuffix(".tsx")) ? .canvas : .markdown
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return WorkingDocument(
                id: id,
                urlPath: id,
                kind: kind,
                projectName: url.deletingLastPathComponent().lastPathComponent,
                fileName: url.lastPathComponent,
                relativePath: url.lastPathComponent,
                modifiedAt: values?.contentModificationDate ?? .distantPast,
                fileSize: Int64(values?.fileSize ?? 0)
            )
        }
    }

    func openRecent(id: String) {
        if let doc = recentDocuments.first(where: { $0.id == id }) {
            select(doc)
            return
        }
        let url = URL(fileURLWithPath: id)
        guard FileManager.default.fileExists(atPath: id) else {
            statusMessage = "Recent file no longer exists"
            recentIDs.removeAll { $0 == id }
            defaults.set(recentIDs, forKey: recentKey)
            return
        }
        let name = url.lastPathComponent.lowercased()
        let kind: DocumentKind =
            (name.hasSuffix(".canvas.tsx") || name.hasSuffix(".tsx")) ? .canvas : .markdown
        let doc = WorkingDocument(
            id: id,
            urlPath: id,
            kind: kind,
            projectName: url.deletingLastPathComponent().lastPathComponent,
            fileName: url.lastPathComponent,
            relativePath: url.lastPathComponent,
            modifiedAt: Date(),
            fileSize: 0
        )
        select(doc)
    }

    // MARK: - Helpers

    static var supportedOpenTypes: [UTType] {
        ["tsx", "md", "markdown", "jsx", "ts", "js"].compactMap { UTType(filenameExtension: $0) }
        + [.plainText, .sourceCode]
    }
}
