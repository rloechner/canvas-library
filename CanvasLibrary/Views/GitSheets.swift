//
//  GitSheets.swift
//  Canvas Library
//
//  Diff + commit sheets for the open document.
//

import AppKit
import SwiftUI

struct GitDiffSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Diff")
                    .font(.headline)
                if let name = app.openDoc?.fileName {
                    Text("· \(name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let label = app.gitFileStatusLabel {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.14))
                        .foregroundStyle(.indigo)
                        .clipShape(Capsule())
                }
                Spacer()
                if app.isGitBusy {
                    ProgressView().controlSize(.small)
                }
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Picker("Side", selection: $app.gitDiffShowsStaged) {
                Text("Working tree").tag(false)
                Text("Staged").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .onChange(of: app.gitDiffShowsStaged) { _, _ in
                app.loadGitDiff()
            }

            ScrollView {
                Text(app.gitDiffText.isEmpty ? "Loading…" : app.gitDiffText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor))

            HStack(spacing: 10) {
                if app.canDiscardGitChanges {
                    Button(role: .destructive) {
                        app.discardGitChanges()
                    } label: {
                        Label("Discard Changes", systemImage: "arrow.counterclockwise")
                    }
                    .help("Restore this file to the last commit")
                    .disabled(app.isGitBusy)
                }

                Spacer()

                if app.canStageCurrentFile {
                    Button {
                        app.stageCurrentFile()
                    } label: {
                        Label("Stage", systemImage: "plus.circle")
                    }
                    .disabled(app.isGitBusy)
                }
                if app.canUnstageCurrentFile {
                    Button {
                        app.unstageCurrentFile()
                    } label: {
                        Label("Unstage", systemImage: "minus.circle")
                    }
                    .disabled(app.isGitBusy)
                }
                if app.canCommitCurrentFile {
                    Button {
                        dismiss()
                        app.presentGitCommit()
                    } label: {
                        Label("Commit…", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(app.isGitBusy)
                }
            }
            .controlSize(.small)
            .padding(12)
            .background(.bar)
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            app.loadGitDiff()
        }
        .onChange(of: app.gitFileStatus) { _, _ in
            // Refresh text after stage / discard from this sheet.
            if app.showGitDiffSheet {
                app.loadGitDiff()
            }
        }
    }
}

struct GitCommitSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var messageFocused: Bool

    private var canCommit: Bool {
        !app.gitCommitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !app.isGitBusy
            && app.openDoc != nil
            && app.isInGitRepo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Commit")
                .font(.title2.weight(.semibold))

            if let doc = app.openDoc {
                VStack(alignment: .leading, spacing: 4) {
                    Text(doc.fileName)
                        .font(.body.weight(.medium))
                    if let branch = app.gitBranch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let label = app.gitFileStatusLabel {
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    Text(doc.urlPath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            Text("Message")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $app.gitCommitMessage)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 160)
                .focused($messageFocused)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }

            Text("Commits only this file. If it isn’t staged yet, it will be staged first.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Cancel") {
                    app.showGitCommitSheet = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Commit") {
                    app.commitCurrentFile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCommit)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            messageFocused = true
            app.refreshGitState()
        }
    }
}
