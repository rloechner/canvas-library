//
//  EmptyStateView.swift
//  CanvasSpace
//

import SwiftUI

struct EmptyStateView: View {
    let onOpen: () -> Void
    let onRefresh: () -> Void
    let onAddFolder: () -> Void
    let documentCount: Int
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "books.vertical")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("Canvas Library")
                    .font(.largeTitle.weight(.semibold))
                Text("Your working Cursor documents — canvases and markdown — in their own space.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            if documentCount > 0 {
                Text("\(documentCount) documents in your library")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Select a document in the sidebar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Button(action: onOpen) {
                    Label("Open File…", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)

                Button(action: onRefresh) {
                    Label("Scan Library", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: onAddFolder) {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Text("Scans ~/.cursor/projects/*/canvases  ·  drop files here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.primary.opacity(0.08),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [6, 4])
                )
                .padding(24)
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
        )
    }
}
