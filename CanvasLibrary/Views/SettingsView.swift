//
//  SettingsView.swift
//  Canvas Library
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                if app.spaces.isEmpty {
                    Text("No folders yet. Add a folder of canvases or markdown, or optionally add Cursor’s canvases directory.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(app.spaces) { space in
                    HStack(alignment: .center, spacing: 10) {
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
                        HStack(spacing: 4) {
                            Button {
                                app.moveExtraSpace(id: space.id, direction: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(app.spaces.first?.id == space.id)
                            .help("Move up")

                            Button {
                                app.moveExtraSpace(id: space.id, direction: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(app.spaces.last?.id == space.id)
                            .help("Move down")

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
                        app.addCursorCanvasesSpace()
                    } label: {
                        Label("Add Cursor Canvases…", systemImage: "shippingbox")
                    }
                    Button {
                        app.refreshLibrary()
                    } label: {
                        Label("Rescan", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(app.spaces.isEmpty)
                }
            } header: {
                Text("Library folders")
            } footer: {
                Text("Only folders you add are scanned for .canvas.tsx and .md. Removing a folder only detaches it from the library — files stay on disk.")
            }

            Section("Show in sidebar") {
                Picker("Document kinds", selection: $app.filter) {
                    ForEach(LibraryFilter.allCases) { f in
                        Text(f.title).tag(f)
                    }
                }
                .pickerStyle(.segmented)
            }

            if !app.hiddenProjects.isEmpty || !app.excludedFolders.isEmpty {
                Section {
                    if !app.hiddenProjects.isEmpty {
                        ForEach(app.hiddenProjects.sorted(), id: \.self) { name in
                            HStack {
                                Text(name)
                                Spacer()
                                Button("Show") {
                                    app.unhideProject(name)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button("Show All Hidden Projects") {
                            app.unhideAllProjects()
                        }
                    }
                    if !app.excludedFolders.isEmpty {
                        ForEach(app.excludedFolders.sorted(), id: \.self) { key in
                            HStack {
                                Text(prettyExclusion(key))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Show") {
                                    if let range = key.range(of: "//") {
                                        let project = String(key[..<range.lowerBound])
                                        let folder = String(key[range.upperBound...])
                                        app.includeFolder(project: project, folderPath: folder)
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button("Show All Hidden Folders") {
                            app.clearExcludedFolders()
                        }
                    }
                } header: {
                    Text("Hidden in sidebar")
                } footer: {
                    Text("Hiding never deletes files. Right‑click a project or folder in the sidebar to hide it.")
                }
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
        .frame(width: 540, height: 540)
    }

    private func prettyExclusion(_ key: String) -> String {
        guard let range = key.range(of: "//") else { return key }
        let project = String(key[..<range.lowerBound])
        let folder = String(key[range.upperBound...])
        return "\(project)/\(folder)"
    }
}
