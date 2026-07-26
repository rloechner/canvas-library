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
            // While searching, force-expand projects that have matches.
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

// MARK: - Project section (root of Finder tree)

private struct ProjectSection: View {
    @EnvironmentObject private var app: AppModel
    let projectName: String

    private var tree: [LibraryTreeNode] {
        app.libraryTree(for: projectName)
    }

    private var fileCount: Int {
        tree.reduce(0) { $0 + $1.fileCount }
    }

    private var isExpandedBinding: Binding<Bool> {
        Binding(
            get: {
                if !app.searchText.isEmpty { return true }
                return app.expandedProjects.contains(projectName)
            },
            set: { expanded in
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
            ForEach(tree) { node in
                TreeNodeView(node: node, projectName: projectName)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(width: 14)
                Text(projectName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(fileCount)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Recursive folder / file nodes

private struct TreeNodeView: View {
    @EnvironmentObject private var app: AppModel
    let node: LibraryTreeNode
    let projectName: String

    var body: some View {
        switch node {
        case .folder(let id, let name, let relativePath, let children, let fileCount):
            FolderSection(
                id: id,
                name: name,
                relativePath: relativePath,
                children: children,
                fileCount: fileCount,
                projectName: projectName
            )
        case .file(let doc):
            DocumentRow(doc: doc)
                .tag(doc.id)
        }
    }
}

private struct FolderSection: View {
    @EnvironmentObject private var app: AppModel
    let id: String
    let name: String
    let relativePath: String
    let children: [LibraryTreeNode]
    let fileCount: Int
    let projectName: String

    private var isExpandedBinding: Binding<Bool> {
        Binding(
            get: { app.isFolderExpanded(project: projectName, folderPath: relativePath) },
            set: { app.setFolderExpanded(project: projectName, folderPath: relativePath, expanded: $0) }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpandedBinding) {
            ForEach(children) { child in
                TreeNodeView(node: child, projectName: projectName)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                    .font(.caption)
                    .frame(width: 14)
                Text(name)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(fileCount)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .id(id)
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
        .help(doc.relativePath == doc.fileName ? doc.urlPath : "\(doc.projectName)/\(doc.relativePath)")
    }
}
