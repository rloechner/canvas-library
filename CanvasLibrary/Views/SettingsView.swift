//
//  SettingsView.swift
//  CanvasSpace
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Form {
            Section("Library spaces") {
                ForEach(app.spaces) { space in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(space.name)
                            Text(space.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if space.id != "cursor-all-canvases" {
                            Button("Remove") {
                                app.removeSpace(space)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Button("Add Folder…") {
                    app.addFolderSpace()
                }
                Button("Rescan Library") {
                    app.refreshLibrary()
                }
            }

            Section("Editor") {
                Toggle("Show line numbers", isOn: $app.showLineNumbers)
                HStack {
                    Text("Font size")
                    Slider(value: $app.fontSize, in: 11...20, step: 1)
                    Text("\(Int(app.fontSize))pt")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            Section("About") {
                Text("Canvas Library is a companion for Cursor working documents — canvases and markdown — so you can find, cycle, preview, and lightly edit them outside the IDE.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 380)
        .padding()
    }
}
