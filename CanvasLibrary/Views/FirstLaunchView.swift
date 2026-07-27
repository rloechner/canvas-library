//
//  FirstLaunchView.swift
//  Canvas Library
//
//  One-time setup: user picks library folders. No auto-scan of Cursor projects.
//

import SwiftUI

struct FirstLaunchView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.25), Color.purple.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.purple.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .padding(.top, 8)

                Text("Welcome to Canvas Library")
                    .font(.title2.weight(.semibold))

                Text("Choose folders that hold your working documents — Cursor canvases (`.canvas.tsx`) and markdown. Nothing is scanned until you pick a location.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 24)

            VStack(spacing: 10) {
                Button {
                    app.addFolderSpace()
                } label: {
                    Label("Add Folder…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    app.addCursorCanvasesSpace()
                } label: {
                    Label("Add Cursor Canvases…", systemImage: "shippingbox")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Scan ~/.cursor/projects/*/canvases (optional — you can remove this space later)")

                Button {
                    app.completeSetupEmpty()
                } label: {
                    Text("Start Empty")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .controlSize(.large)
                .padding(.top, 4)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 12)

            Text("You can add or remove folders anytime from the toolbar or Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
