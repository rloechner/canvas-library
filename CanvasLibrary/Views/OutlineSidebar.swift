//
//  OutlineSidebar.swift
//  Canvas Library
//
//  Canvas structure outline — jump to line in the source editor.
//

import SwiftUI

struct OutlinePopover: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Outline")
                    .font(.headline)
                Spacer()
                Text("\(app.outline.count) top-level")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if app.outline.isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach(app.outline) { node in
                        OutlineRow(node: node, depth: 0) { app.jumpToOutline($0) }
                    }
                }
                .listStyle(.sidebar)
                .frame(minHeight: 180, maxHeight: 360)
            }
        }
        .frame(width: 280)
    }

    private var emptyMessage: String {
        guard let doc = app.openDoc else {
            return "Open a document to see its outline."
        }
        switch doc.kind {
        case .canvas:
            return "No components detected in this canvas yet."
        case .markdown:
            return "Outline is available for canvas (TSX) structure."
        }
    }
}

private struct OutlineRow: View {
    let node: OutlineNode
    let depth: Int
    let onSelect: (OutlineNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                onSelect(node)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: node.kind.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(node.name)
                        .lineLimit(1)
                        .font(.body)
                    Spacer(minLength: 4)
                    Text(node.lineLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, CGFloat(depth) * 12)

            ForEach(node.children) { child in
                OutlineRow(node: child, depth: depth + 1, onSelect: onSelect)
            }
        }
    }
}
