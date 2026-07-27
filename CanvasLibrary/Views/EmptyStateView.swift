//
//  EmptyStateView.swift
//  Canvas Library
//

import SwiftUI

struct EmptyStateView: View {
    let onOpen: () -> Void
    let onRefresh: () -> Void
    let onAddFolder: () -> Void
    let documentCount: Int
    let isTargeted: Bool
    var isScanning: Bool = false

    var body: some View {
        ZStack {
            // Soft ambient background
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.04),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                VStack(spacing: 28) {
                    iconBadge

                    VStack(spacing: 10) {
                        Text("Canvas Library")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("Your Cursor canvases and markdown — browse, preview, and lightly edit without hunting projects.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isScanning && documentCount == 0 {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Scanning Cursor projects…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if documentCount > 0 {
                        libraryPill
                    } else {
                        Text("No documents yet — scan your Cursor projects or open a file.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 10) {
                        Button(action: onOpen) {
                            Label("Open File…", systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut("o", modifiers: .command)

                        Button(action: onRefresh) {
                            Label("Rescan Library", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(isScanning)

                        Button(action: onAddFolder) {
                            Label("Add Folder", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(.top, 4)

                    Text("Scans ~/.cursor/projects/*/canvases  ·  drop files here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
                .padding(36)
                .frame(maxWidth: 520)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.06), radius: 24, y: 8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.primary.opacity(0.06),
                            lineWidth: isTargeted ? 2 : 1
                        )
                }
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
                .scaleEffect(isTargeted ? 1.01 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isTargeted)

                Spacer(minLength: 24)
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.22),
                            Color.purple.opacity(0.14),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 88, height: 88)
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor, Color.purple.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var libraryPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.small)
            Text("\(documentCount) document\(documentCount == 1 ? "" : "s") ready")
                .font(.subheadline.weight(.medium))
            Text("·")
                .foregroundStyle(.tertiary)
            Text("Select one in the sidebar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: Capsule())
    }
}
