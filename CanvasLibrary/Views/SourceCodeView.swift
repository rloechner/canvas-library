//
//  SourceCodeView.swift
//  Canvas Library
//
//  Source pane: Monaco editor. Save / Format / Revert live in the window toolbar.
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
            HStack(spacing: 8) {
                Circle()
                    .fill(isDirty ? Color.orange : Color.green.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(isDirty ? "Unsaved" : "Saved")
                Text(isDirty ? "Unsaved" : "Saved")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isDirty ? Color.orange : Color.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(fileName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            MonacoEditorView(
                text: text,
                language: monacoLanguage,
                fontSize: fontSize,
                showLineNumbers: showLineNumbers,
                isDark: isDark,
                isEditable: isEditable,
                documentID: documentID,
                scrollToLine: scrollToLine,
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
        default: return "typescript"
        }
    }
}
