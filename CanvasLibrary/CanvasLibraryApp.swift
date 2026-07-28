//
//  CanvasLibraryApp.swift
//  Canvas Library
//
//  Companion app for Cursor working documents (canvases + markdown).
//

import AppKit
import SwiftUI

@main
struct CanvasLibraryApp: App {
    @StateObject private var appModel = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    appDelegate.bind(appModel)
                    NSApp.setActivationPolicy(.regular)
                    appModel.ensureLibraryLoaded()
                }
                .onOpenURL { url in
                    openURL(url)
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    appModel.openFilePanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Refresh Library") {
                    appModel.refreshLibrary()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Add Folder Space…") {
                    appModel.addFolderSpace()
                }

                Button("Add Cursor Canvases…") {
                    appModel.addCursorCanvasesSpace()
                }

                Divider()

                Button("Previous Document") {
                    appModel.goPrev()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!appModel.canGoPrev)

                Button("Next Document") {
                    appModel.goNext()
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!appModel.canGoNext)

                Divider()

                Menu("Open Recent") {
                    let recents = appModel.recentDocuments
                    if recents.isEmpty {
                        Text("No Recent Documents")
                    } else {
                        ForEach(recents.prefix(12)) { doc in
                            Button("\(doc.displayTitle)  —  \(doc.projectName)") {
                                appModel.openRecent(id: doc.id)
                            }
                        }
                    }
                }
            }

            CommandGroup(after: .pasteboard) {
                Button("Reload Preview") {
                    appModel.recompileOrRefresh()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appModel.openDoc == nil)

                Button("Format Document") {
                    appModel.formatDocument()
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(appModel.openDoc == nil)

                Button("Save") {
                    appModel.saveDocument()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(appModel.openDoc == nil || !appModel.isDirty)

                Button("Revert Unsaved Changes") {
                    appModel.revertDocument()
                }
                // No ⌘⇧Z — that chord is system Redo / Monaco redo.
                .disabled(appModel.openDoc == nil || !appModel.isDirty)

                Button("Copy Source") {
                    appModel.copyBuffer()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(appModel.openDoc == nil)

                Divider()

                Button("Show Git Diff…") {
                    appModel.presentGitDiff()
                }
                .disabled(appModel.openDoc == nil || !appModel.isInGitRepo || !appModel.gitFileInWorktree)

                Button("Discard Git Changes…") {
                    appModel.discardGitChanges()
                }
                .disabled(appModel.openDoc == nil || !appModel.canDiscardGitChanges)

                Button(appModel.canUnstageCurrentFile ? "Unstage File" : "Stage File") {
                    if appModel.canUnstageCurrentFile {
                        appModel.unstageCurrentFile()
                    } else {
                        appModel.stageCurrentFile()
                    }
                }
                .disabled(appModel.openDoc == nil || !appModel.isInGitRepo || appModel.isGitBusy
                          || (!appModel.canUnstageCurrentFile && !appModel.canStageCurrentFile))

                Button("Commit File…") {
                    appModel.presentGitCommit()
                }
                .disabled(appModel.openDoc == nil || !appModel.canCommitCurrentFile)
            }

            CommandGroup(replacing: .importExport) {
                Button("Export as PDF…") {
                    appModel.exportPDF()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appModel.openDoc == nil || appModel.isExportingPDF)
            }

            CommandGroup(replacing: .printItem) {
                Button("Print…") {
                    appModel.printDocument()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(appModel.openDoc == nil || appModel.isExportingPDF)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }

    private func openURL(_ url: URL) {
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
        appModel.select(doc)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var appModel: AppModel?
    private var pendingURLs: [URL] = []

    func bind(_ model: AppModel) {
        appModel = model
        guard !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        for url in urls {
            openFile(url, into: model)
        }
    }

    nonisolated func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            if let appModel {
                for url in urls { openFile(url, into: appModel) }
            } else {
                pendingURLs.append(contentsOf: urls)
            }
        }
    }

    nonisolated func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        Task { @MainActor in
            if let appModel {
                openFile(url, into: appModel)
            } else {
                pendingURLs.append(url)
            }
        }
        return true
    }

    @MainActor
    private func openFile(_ url: URL, into model: AppModel) {
        let name = url.lastPathComponent.lowercased()
        let kind: DocumentKind = (name.hasSuffix(".canvas.tsx") || name.hasSuffix(".tsx")) ? .canvas : .markdown
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
        model.select(doc)
    }
}
