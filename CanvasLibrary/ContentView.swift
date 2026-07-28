//
//  ContentView.swift
//  Canvas Library
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropTargeted = false
    @State private var sidebarWidth: CGFloat = 300

    var body: some View {
        // HSplitView (not NavigationSplitView): NSSplitView lays out inside the
        // window content area. NavigationSplitView was sizing the split ~2× the
        // window height and drawing the outline above the titlebar.
        NavigationStack {
            HSplitView {
                LibrarySidebar()
                    .frame(minWidth: 240, idealWidth: sidebarWidth, maxWidth: 420)
                    .layoutPriority(0)

                detail
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            }
            .navigationTitle(app.openDoc?.displayTitle ?? "Canvas Library")
            .toolbar { libraryToolbar; mainToolbar }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { handleDrop($0) }
        .onAppear {
            app.ensureLibraryLoaded()
            app.refreshCanvasEnvironment()
        }
        .sheet(isPresented: Binding(
            get: { app.needsSetup },
            set: { presented in
                // Dismiss without choosing → start empty (utility-friendly).
                if !presented, app.needsSetup {
                    app.completeSetupEmpty()
                }
            }
        )) {
            FirstLaunchView()
                .environmentObject(app)
        }
        .sheet(isPresented: $app.showGitDiffSheet) {
            GitDiffSheet()
                .environmentObject(app)
        }
        .sheet(isPresented: $app.showGitCommitSheet) {
            GitCommitSheet()
                .environmentObject(app)
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                app.refreshLibrary()
            } label: {
                Label("Rescan", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Rescan your library folders")
            .disabled(app.spaces.isEmpty)

            Button {
                app.addFolderSpace()
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .help("Add a folder of canvases or markdown")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if app.openDoc != nil {
            VStack(spacing: 0) {
                documentHeader
                Divider()
                contentPane
                statusBar
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
        } else {
            EmptyStateView(
                onOpen: app.openFilePanel,
                onRefresh: { app.refreshLibrary() },
                onAddFolder: app.addFolderSpace,
                documentCount: app.documents.count,
                isTargeted: isDropTargeted,
                isScanning: app.isScanning
            )
        }
    }

    private var documentHeader: some View {
        VStack(spacing: 0) {
            if app.externalFileChangePending {
                externalChangeBanner
            }
            HStack(spacing: 12) {
            if let doc = app.openDoc {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((doc.kind == .canvas ? Color.purple : Color.blue).opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: doc.kind.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(doc.kind == .canvas ? .purple : .blue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(doc.displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                        kindBadge(doc.kind)
                        if app.isDirty {
                            Text("Unsaved")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.16))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                        if let gitLabel = app.gitFileStatusLabel {
                            Text(gitLabel)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.indigo.opacity(0.14))
                                .foregroundStyle(.indigo)
                                .clipShape(Capsule())
                                .help("Git status for this file")
                        }
                    }
                    Text(pathSubtitle(for: doc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            // Buffer dirty: Save + Revert (last saved on disk)
            if app.isDirty {
                Button {
                    app.revertDocument()
                } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Discard unsaved edits and restore the last saved version")

                Button {
                    app.saveDocument()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Save to disk (⌘S)")
                .keyboardShortcut("s", modifiers: .command)
            }

            // Only show git actions when the open file is actually inside a worktree.
            // Cursor cache canvases often resolve a repo root but live outside it —
            // disabled chrome there was more confusing than helpful.
            if app.isInGitRepo, app.gitFileInWorktree {
                HStack(spacing: 4) {
                    Button {
                        app.presentGitDiff()
                    } label: {
                        Label("Diff", systemImage: "doc.text.magnifyingglass")
                    }
                    .help("Show git diff for this file")

                    // After save: file may still be modified vs HEAD — offer discard.
                    if app.canDiscardGitChanges {
                        Button {
                            app.discardGitChanges()
                        } label: {
                            Label("Discard", systemImage: "arrow.counterclockwise")
                        }
                        .help("Discard uncommitted changes and restore the last commit")
                        .disabled(app.isGitBusy)
                    }

                    if app.canUnstageCurrentFile {
                        Button {
                            app.unstageCurrentFile()
                        } label: {
                            Label("Unstage", systemImage: "minus.circle")
                        }
                        .help("Unstage this file")
                        .disabled(app.isGitBusy)
                    } else {
                        Button {
                            app.stageCurrentFile()
                        } label: {
                            Label("Stage", systemImage: "plus.circle")
                        }
                        .help("Stage this file")
                        .disabled(app.isGitBusy || !app.canStageCurrentFile)
                    }

                    Button {
                        app.presentGitCommit()
                    } label: {
                        Label("Commit", systemImage: "checkmark.circle")
                    }
                    .help("Commit this file")
                    .disabled(app.isGitBusy || !app.canCommitCurrentFile)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 4) {
                Button { app.goPrev() } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(!app.canGoPrev)
                .help("Previous document (⌘↑)")
                .keyboardShortcut(.upArrow, modifiers: .command)

                Button { app.goNext() } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(!app.canGoNext)
                .help("Next document (⌘↓)")
                .keyboardShortcut(.downArrow, modifiers: .command)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if app.openDoc?.kind == .canvas, app.viewMode == .preview {
                Toggle(isOn: Binding(
                    get: { app.isDesignMode },
                    set: { app.setDesignMode($0) }
                )) {
                    Label(
                        app.isDesignMode ? "Editing preview" : "Edit in preview",
                        systemImage: app.isDesignMode ? "pencil.and.outline" : "hand.tap"
                    )
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(app.isDesignMode ? .blue : nil)
                .help("Click text in the live preview to edit source (then Save)")
            }

            } // HStack
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
            .onChange(of: app.viewMode) { _, mode in
                if mode == .source {
                    app.setDesignMode(false)
                }
            }
        } // VStack
    }

    private var externalChangeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("This file changed on disk while you have unsaved edits.")
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Button("Keep Editing") {
                app.dismissExternalFileChange()
            }
            .controlSize(.small)
            Button("Reload from Disk") {
                app.reloadOpenDocumentFromDisk()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private func kindBadge(_ kind: DocumentKind) -> some View {
        Text(kind.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((kind == .canvas ? Color.purple : Color.blue).opacity(0.14))
            .foregroundStyle(kind == .canvas ? .purple : .blue)
            .clipShape(Capsule())
    }

    private func pathSubtitle(for doc: WorkingDocument) -> String {
        if doc.folderPath.isEmpty {
            return "\(doc.projectName)  ·  \(doc.fileName)"
        }
        return "\(doc.projectName)/\(doc.folderPath)  ·  \(doc.fileName)"
    }

    @ViewBuilder
    private var contentPane: some View {
        ZStack {
            switch app.viewMode {
            case .source:
                SourceCodeView(
                    text: app.bufferText,
                    originalText: app.originalText,
                    language: app.editorLanguage,
                    fontSize: app.fontSize,
                    showLineNumbers: app.showLineNumbers,
                    scrollToLine: app.pendingScrollToLine,
                    isEditable: true,
                    isDark: colorScheme == .dark,
                    isDirty: app.isDirty,
                    documentID: "\(app.openDoc?.id ?? "none")-\(app.editorReloadNonce.uuidString)",
                    fileName: app.openDoc?.fileName ?? "",
                    onTextChange: { app.updateBuffer($0) },
                    onSave: { app.saveDocument() },
                    onRevert: { app.revertDocument() },
                    onFormat: { app.formatDocument() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id("source-\(app.openDoc?.id ?? "none")")

            case .preview:
                if let doc = app.openDoc {
                    switch doc.kind {
                    case .canvas:
                        canvasPreviewPane
                    case .markdown:
                        MarkdownPreviewView(
                            markdown: app.bufferText,
                            isDark: colorScheme == .dark,
                            reloadToken: app.markdownReloadToken
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: TSXHighlighter.Theme.current().background))
        .clipped()
    }

    private var canvasPreviewPane: some View {
        // No full-width unlock banner — header toggle + status bar carry “editing preview”.
        VStack(spacing: 0) {
            ZStack {
                CanvasPreviewView(
                    hostURL: app.canvasHostURL,
                    workDirectory: app.canvasWorkDirectory,
                    reloadToken: app.canvasReloadToken,
                    isVisible: true,
                    designMode: app.isDesignMode,
                    onReady: { app.canvasDidReady() },
                    onError: { app.canvasDidFail($0) },
                    onDesignTextEdit: { old, new in
                        app.applyPreviewTextEdit(oldText: old, newText: new)
                    }
                )
                // Stable identity for the open doc — do not key on dirty/status or the
                // WebView remounts (full rebuild + scroll jump) on every buffer edit.
                .id("canvas-preview-\(app.openDoc?.id ?? "none")")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if app.isCompiling {
                    ProgressView("Compiling canvas…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                if let error = app.canvasError, !app.isCompiling {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Could not render canvas")
                            .font(.headline)
                        ScrollView {
                            Text(error)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: 560, alignment: .leading)
                        }
                        .frame(maxHeight: 140)
                        if !app.canvasEnvironment.isReadyForCanvasPreview {
                            Text(app.canvasEnvironment.shortSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 420)
                        }
                        HStack {
                            Button("Show Source") { app.viewMode = .source }
                            Button("Retry") {
                                app.refreshCanvasEnvironment()
                                app.compileCanvas(force: true)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if app.isFormatting || app.isCompiling || app.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(busyStatusText)
            } else if app.isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("Unsaved changes")
                    .help("Unsaved changes")
            } else if app.gitFileStatus.isChanged {
                Circle()
                    .fill(Color.indigo.opacity(0.85))
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(app.gitFileStatusLabel ?? "Modified")
                    .help(app.gitFileStatusLabel.map { "Git: \($0)" } ?? "Uncommitted changes")
            } else if app.openDoc != nil {
                Circle()
                    .fill(Color.green.opacity(0.75))
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("Saved")
                    .help(app.isInGitRepo && app.gitFileInWorktree ? "Saved · matches git" : "Saved")
            }

            Text(primaryStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if app.openDoc?.kind == .canvas {
                Text("·")
                    .foregroundStyle(.quaternary)
                Image(systemName: app.canvasEnvironment.isReadyForCanvasPreview
                      ? (app.canvasEnvironment.isLimitedRuntime ? "cube.transparent" : "cube")
                      : "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(app.canvasEnvironment.isReadyForCanvasPreview
                                     ? (app.canvasEnvironment.isLimitedRuntime ? Color.orange : Color.secondary)
                                     : Color.orange)
                    .help(app.canvasEnvironment.helpDetail)
            }

            if app.isInGitRepo, app.gitFileInWorktree, let branch = app.gitBranch {
                Text("·")
                    .foregroundStyle(.quaternary)
                Label(branch, systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help({
                        var h = app.gitRootPath.map { "Git: \($0)" } ?? "Git"
                        if let label = app.gitFileStatusLabel {
                            h += " · \(label)"
                        }
                        return h
                    }())
            }

            if app.isGitBusy {
                ProgressView()
                    .controlSize(.small)
                    .help("Git…")
            }

            Spacer(minLength: 8)

            if app.openDoc != nil {
                let lines = app.bufferText.split(separator: "\n", omittingEmptySubsequences: false).count
                Text("\(lines) lines")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("\(app.bufferText.count) chars")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            } else {
                Text("\(app.documents.count) in library")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var busyStatusText: String {
        if app.isScanning { return "Scanning library…" }
        if app.isCompiling { return "Compiling canvas…" }
        if app.isFormatting { return "Formatting…" }
        return app.statusMessage ?? ""
    }

    private var primaryStatusText: String {
        if app.isScanning || app.isCompiling || app.isFormatting {
            return busyStatusText
        }
        return app.statusMessage ?? ""
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("View", selection: $app.viewMode) {
                Image(systemName: "eye")
                    .help("Preview")
                    .tag(ViewMode.preview)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .help("Source")
                    .tag(ViewMode.source)
            }
            .pickerStyle(.segmented)
            .frame(width: 90)
            .disabled(app.openDoc == nil)
            .help("Preview or Source")

            Button { app.openFilePanel() } label: {
                Label("Open", systemImage: "folder")
            }
            .help("Open a file (⌘O)")

            Button { app.recompileOrRefresh() } label: {
                Label("Reload Preview", systemImage: "arrow.clockwise")
            }
            .disabled(app.openDoc == nil || app.isCompiling)
            .help("Reload preview (⌘R)")

            Button { app.formatDocument() } label: {
                Label("Format", systemImage: "wand.and.stars")
            }
            .disabled(app.openDoc == nil || app.isFormatting)
            .help("Format document (⌥⌘F)")

            if app.openDoc?.kind == .canvas {
                Menu {
                    if app.outline.isEmpty {
                        Text("No outline symbols")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(flattenedOutline(app.outline), id: \.id) { item in
                            Button("\(String(repeating: "  ", count: item.depth))\(item.node.name)  L\(item.node.line)") {
                                app.jumpToOutline(item.node)
                            }
                        }
                    }
                } label: {
                    Label("Outline", systemImage: "list.bullet.indent")
                }
                .help("Jump to a canvas component in Source")
            }

            Button {
                if app.isDirty {
                    app.revertDocument()
                } else if app.canDiscardGitChanges {
                    app.discardGitChanges()
                }
            } label: {
                Label(
                    app.isDirty ? "Revert" : "Discard",
                    systemImage: app.isDirty ? "arrow.uturn.backward" : "arrow.counterclockwise"
                )
            }
            .disabled(app.openDoc == nil || (!app.isDirty && !app.canDiscardGitChanges))
            .help(app.isDirty
                  ? "Discard unsaved edits (restore last save)"
                  : "Discard uncommitted git changes (restore last commit)")

            Button { app.saveDocument() } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(app.openDoc == nil || !app.isDirty)
            .keyboardShortcut("s", modifiers: .command)
            .help("Save to disk (⌘S)")

            Button { app.exportPDF() } label: {
                Label("Export PDF", systemImage: "doc.richtext")
            }
            .disabled(app.openDoc == nil || app.isExportingPDF)
            .help("Export current document as PDF (⇧⌘E)")

            Button { app.printDocument() } label: {
                Label("Print", systemImage: "printer")
            }
            .disabled(app.openDoc == nil || app.isExportingPDF)
            .help("Print current document (⌘P)")

            Button { app.copyBuffer() } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(app.openDoc == nil)
            .help("Copy source to clipboard")

            Button { app.revealInFinder() } label: {
                Label("Show in Finder", systemImage: "finder")
            }
            .disabled(app.openDoc == nil)
            .help("Reveal file in Finder")
        }
    }

    private struct FlatOutlineItem: Identifiable {
        var id: String { "\(node.id)-\(depth)" }
        let node: OutlineNode
        let depth: Int
    }

    private func flattenedOutline(_ nodes: [OutlineNode], depth: Int = 0) -> [FlatOutlineItem] {
        var items: [FlatOutlineItem] = []
        for node in nodes {
            items.append(FlatOutlineItem(node: node, depth: depth))
            items.append(contentsOf: flattenedOutline(node.children, depth: depth + 1))
        }
        return items
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let u = item as? URL {
                        url = u
                    } else if let s = item as? String {
                        url = URL(fileURLWithPath: s)
                    } else {
                        url = nil
                    }
                    if let url {
                        DispatchQueue.main.async {
                            let name = url.lastPathComponent.lowercased()
                            let kind: DocumentKind
                            if name.hasSuffix(".canvas.tsx") || name.hasSuffix(".tsx") {
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
                                modifiedAt: Date(),
                                fileSize: 0
                            )
                            app.select(doc)
                        }
                    }
                }
                handled = true
            }
        }
        return handled
    }
}
