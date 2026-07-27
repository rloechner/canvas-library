//
//  SettingsView.swift
//  Canvas Library
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "3"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                ForEach(app.spaces) { space in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: space.recursiveCanvases ? "shippingbox" : "folder")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(space.name)
                                .font(.body.weight(.medium))
                            Text(space.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        if space.id != "cursor-all-canvases" {
                            Button("Remove", role: .destructive) {
                                app.removeSpace(space)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    Button {
                        app.addFolderSpace()
                    } label: {
                        Label("Add Folder…", systemImage: "folder.badge.plus")
                    }
                    Button {
                        app.refreshLibrary()
                    } label: {
                        Label("Rescan", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            } header: {
                Text("Library spaces")
            } footer: {
                Text("By default Canvas Library scans ~/.cursor/projects/*/canvases. Add extra folders for docs outside Cursor.")
            }

            Section("Editor") {
                Toggle("Show line numbers", isOn: $app.showLineNumbers)
                HStack {
                    Text("Font size")
                    Slider(value: $app.fontSize, in: 11...20, step: 1)
                    Text("\(Int(app.fontSize))")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("License", value: "MIT")
                LabeledContent("Bundle ID") {
                    Text("com.ryanloechner.canvaslibrary")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Link(destination: URL(string: "https://github.com/rloechner/canvas-library")!) {
                    Label("GitHub repository", systemImage: "link")
                }
                Link(destination: URL(string: "https://github.com/rloechner/canvas-library/issues")!) {
                    Label("Report an issue", systemImage: "exclamationmark.bubble")
                }
                Text("© \(Calendar.current.component(.year, from: Date())) Ryan Loechner. Independent open-source companion for Cursor canvases and markdown. Not affiliated with Anysphere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Keyboard: ⌘O Open · ⌘⇧R Rescan · ⌘R Reload Preview · ⌥⌘F Format · ⌘S Save")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 460)
    }
}
