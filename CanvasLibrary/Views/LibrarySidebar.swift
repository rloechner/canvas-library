//
//  LibrarySidebar.swift
//  CanvasSpace
//

import SwiftUI

struct LibrarySidebar: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            searchField
            documentList
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(LibraryFilter.allCases) { f in
                        Button {
                            app.filter = f
                        } label: {
                            if app.filter == f {
                                Label(f.title, systemImage: "checkmark")
                            } else {
                                Text(f.title)
                            }
                        }
                    }
                } label: {
                    Label(app.filter.title, systemImage: "line.3.horizontal.decrease.circle")
                }
                .help("Filter by document kind")
            }
        }
        .onChange(of: app.selectedID) { _, _ in
            app.expandProjectForSelection()
        }
        .onChange(of: app.searchText) { _, query in
            guard !query.isEmpty else { return }
            // While searching, always expand projects that have matches.
            var next = app.expandedProjects
            next.formUnion(app.orderedProjectNames)
            app.expandedProjects = next
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $app.searchText)
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
        .padding(.top, 10)
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

            if app.orderedProjectNames.isEmpty, !app.isScanning {
                Text("No documents")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(app.orderedProjectNames, id: \.self) { projectName in
                    ProjectSection(projectName: projectName)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Project section

private struct ProjectSection: View {
    @EnvironmentObject private var app: AppModel
    let projectName: String

    private var docs: [WorkingDocument] {
        app.documents(inProject: projectName)
    }

    private var isExpandedBinding: Binding<Bool> {
        Binding(
            get: {
                if !app.searchText.isEmpty { return true }
                return app.expandedProjects.contains(projectName)
            },
            set: { expanded in
                // Don't persist collapse while search is forcing expansion.
                guard app.searchText.isEmpty else { return }
                if expanded {
                    app.expandedProjects.insert(projectName)
                } else {
                    app.expandedProjects.remove(projectName)
                }
            }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpandedBinding) {
            ForEach(docs) { doc in
                DocumentRow(doc: doc)
                    .tag(doc.id)
            }
        } label: {
            HStack(spacing: 6) {
                Text(projectName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(docs.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Document row

private struct DocumentRow: View {
    let doc: WorkingDocument

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: doc.kind.systemImage)
                .foregroundStyle(doc.kind == .canvas ? Color.purple : Color.blue)
                .frame(width: 16)

            Text(doc.displayTitle)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            Text(Self.relativeFormatter.localizedString(for: doc.modifiedAt, relativeTo: Date()))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 1)
        .help(doc.urlPath)
    }
}
