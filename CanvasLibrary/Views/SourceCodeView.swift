//
//  SourceCodeView.swift
//  CanvasSpace
//
//  Source pane: Monaco (syntax-colored) + standard editor chrome
//  (Save / Revert / Format) matching common code-editor patterns.
//

import SwiftUI

struct SourceCodeView: View {
    let text: String
    let originalText: String
    let language: String
    let fontSize: Double
    let showLineNumbers: Bool
    let scrollToLine: Int?
    let isEditable: Bool
    let isDark: Bool
    let isDirty: Bool
    let documentID: String
    let fileName: String

    var onTextChange: (String) -> Void
    var onSave: () -> Void
    var onRevert: () -> Void
    var onFormat: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()
            MonacoEditorView(
                text: text,
                language: monacoLanguage,
                fontSize: fontSize,
                isDark: isDark,
                isEditable: isEditable,
                documentID: documentID,
                onTextChange: onTextChange,
                onSave: onSave
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var monacoLanguage: String {
        switch language {
        case "markdown", "md": return "markdown"
        case "json": return "json"
        case "css": return "css"
        case "html": return "html"
        case "javascript", "js", "jsx": return "javascript"
        default: return "typescript" // ts / tsx / canvas
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 10) {
            // Dirty / clean status (like VS Code tab)
            HStack(spacing: 6) {
                Circle()
                    .fill(isDirty ? Color.orange : Color.green.opacity(0.7))
                    .frame(width: 8, height: 8)
                Text(isDirty ? "Unsaved changes" : "Saved")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isDirty ? Color.orange : Color.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(fileName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Primary actions — order mirrors common editors: Format · Revert · Save
            Button {
                onFormat()
            } label: {
                Label("Format", systemImage: "wand.and.stars")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Format document (⌥⌘F)")
            .keyboardShortcut("f", modifiers: [.command, .option])

            Button {
                onRevert()
            } label: {
                Label("Revert", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!isDirty)
            .help("Discard unsaved changes and restore last saved version")

            Button {
                onSave()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!isDirty)
            .help("Save to disk (⌘S)")
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
