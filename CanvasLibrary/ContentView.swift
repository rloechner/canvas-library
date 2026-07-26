//
//  ContentView.swift
//  CanvasSpace
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropTargeted = false
    @State private var scrollToLine: Int?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            app.refreshLibrary()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .help("Rescan library folders")

                        Button {
                            app.addFolderSpace()
                        } label: {
                            Label("Add Folder", systemImage: "folder.badge.plus")
                        }
                        .help("Add a custom docs folder")
                    }
                }
        } detail: {
            detail
        }
        .navigationTitle(app.openDoc?.displayTitle ?? "Canvas Library")
        .toolbar { mainToolbar }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { handleDrop($0) }
        .onAppear {
            // Initial scan already in init; refresh keeps library warm
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
                onRefresh: app.refreshLibrary,
                onAddFolder: app.addFolderSpace,
                documentCount: app.documents.count,
                isTargeted: isDropTargeted
            )
        }
    }

    private var documentHeader: some View {
        HStack(spacing: 10) {
            if let doc = app.openDoc {
                Image(systemName: doc.kind.systemImage)
                    .foregroundStyle(doc.kind == .canvas ? .purple : .blue)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(doc.displayTitle)
                            .font(.headline)
                        Text(doc.kind.title.lowercased())
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((doc.kind == .canvas ? Color.purple : Color.blue).opacity(0.15))
                            .foregroundStyle(doc.kind == .canvas ? .purple : .blue)
                            .clipShape(Capsule())
                        if app.isDirty {
                            Text("edited")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(doc.projectName)  ·  \(doc.fileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            // Cycle
            HStack(spacing: 4) {
                Button {
                    app.goPrev()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(!app.canGoPrev)
                .help("Previous document (⌘↑)")
                .keyboardShortcut(.upArrow, modifiers: .command)

                Button {
                    app.goNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(!app.canGoNext)
                .help("Next document (⌘↓)")
                .keyboardShortcut(.downArrow, modifiers: .command)
            }
            .buttonStyle(.bordered)

            // Unlock preview (canvas only)
            if app.openDoc?.kind == .canvas, app.viewMode == .preview {
                Toggle(isOn: Binding(
                    get: { app.isDesignMode },
                    set: { app.setDesignMode($0) }
                )) {
                    Label(
                        app.isDesignMode ? "Unlocked" : "Unlock",
                        systemImage: app.isDesignMode ? "lock.open.fill" : "lock.fill"
                    )
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(app.isDesignMode ? .blue : nil)
                .help("Unlock preview to click and edit text in the canvas")
            }

            if app.isDesignMode, app.viewMode == .preview {
                Button {
                    app.revertDocument()
                } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(!app.isDirty)
                .controlSize(.small)

                Button {
                    app.saveDocument()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!app.isDirty)
                .controlSize(.small)
            }

            Picker("View", selection: $app.viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .labelsHidden()
            .onChange(of: app.viewMode) { _, mode in
                if mode == .source {
                    app.setDesignMode(false)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
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
                    scrollToLine: scrollToLine,
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
        VStack(spacing: 0) {
            if app.isDesignMode {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open.fill")
                        .foregroundStyle(.white)
                    Text("Preview unlocked — click text to edit. Enter commits a field · Esc cancels.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                    Spacer()
                    if app.isDirty {
                        Text("Unsaved")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.2))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.gradient)
            }

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
                        HStack {
                            Button("Show Source") { app.viewMode = .source }
                            Button("Retry") { app.compileCanvas() }
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
        HStack {
            if app.isFormatting || app.isCompiling || app.isScanning {
                ProgressView().controlSize(.small)
            }
            if let status = app.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if app.openDoc != nil {
                let lines = app.bufferText.split(separator: "\n", omittingEmptySubsequences: false).count
                Text("\(lines) lines · \(app.bufferText.count) chars")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            } else {
                Text("\(app.documents.count) in library")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("View", selection: $app.viewMode) {
                Image(systemName: "eye").tag(ViewMode.preview)
                Image(systemName: "chevron.left.forwardslash.chevron.right").tag(ViewMode.source)
            }
            .pickerStyle(.segmented)
            .frame(width: 90)
            .disabled(app.openDoc == nil)

            Button { app.openFilePanel() } label: {
                Label("Open", systemImage: "folder")
            }

            Button { app.recompileOrRefresh() } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(app.openDoc == nil || app.isCompiling)

            Button { app.formatDocument() } label: {
                Label("Format", systemImage: "wand.and.stars")
            }
            .disabled(app.openDoc == nil || app.isFormatting)

            Button { app.revertDocument() } label: {
                Label("Revert", systemImage: "arrow.uturn.backward")
            }
            .disabled(app.openDoc == nil || !app.isDirty)

            Button { app.saveDocument() } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(app.openDoc == nil || !app.isDirty)
            .keyboardShortcut("s", modifiers: .command)

            Button { app.copyBuffer() } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(app.openDoc == nil)

            Button { app.revealInFinder() } label: {
                Label("Show in Finder", systemImage: "finder")
            }
            .disabled(app.openDoc == nil)
        }
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
