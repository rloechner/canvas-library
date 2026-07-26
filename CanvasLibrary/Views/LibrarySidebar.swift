//
//  LibrarySidebar.swift
//  CanvasSpace
//

import SwiftUI

struct LibrarySidebar: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            searchField
            documentList
        }
    }

    private var filterBar: some View {
        Picker("Filter", selection: $app.filter) {
            ForEach(LibraryFilter.allCases) { f in
                Text(f.title).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search documents", text: $app.searchText)
                .textFieldStyle(.plain)
            if !app.searchText.isEmpty {
                Button {
                    app.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var documentList: some View {
        List(selection: Binding(
            get: { app.selectedID },
            set: { newID in
                if let newID, let doc = app.filteredDocuments.first(where: { $0.id == newID }) {
                    app.select(doc)
                }
            }
        )) {
            if app.isScanning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Scanning…").foregroundStyle(.secondary)
                }
            }

            if !app.recentDocuments.isEmpty && app.searchText.isEmpty && app.filter == .all {
                Section("Recent") {
                    ForEach(app.recentDocuments.prefix(6)) { doc in
                        DocumentRow(doc: doc)
                            .tag(doc.id)
                    }
                }
            }

            Section(sectionTitle) {
                if app.filteredDocuments.isEmpty {
                    Text("No documents")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(app.filteredDocuments) { doc in
                        DocumentRow(doc: doc)
                            .tag(doc.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var sectionTitle: String {
        let n = app.filteredDocuments.count
        switch app.filter {
        case .all: return "Library (\(n))"
        case .canvases: return "Canvases (\(n))"
        case .markdown: return "Markdown (\(n))"
        }
    }
}

private struct DocumentRow: View {
    let doc: WorkingDocument

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: doc.kind.systemImage)
                .foregroundStyle(doc.kind == .canvas ? Color.purple : Color.blue)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(doc.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(doc.kind.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background((doc.kind == .canvas ? Color.purple : Color.blue).opacity(0.12))
                        .foregroundStyle(doc.kind == .canvas ? Color.purple : Color.blue)
                        .clipShape(Capsule())
                    Text(doc.projectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(doc.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .help(doc.urlPath)
    }
}
