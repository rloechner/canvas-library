//
//  LibrarySidebar.swift
//  Canvas Library
//

import SwiftUI

struct LibrarySidebar: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            searchField
            documentList
            sidebarFooter
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
            var next = app.expandedProjects
            next.formUnion(app.orderedProjectNames)
            app.expandedProjects = next
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search library", text: $app.searchText)
                .textFieldStyle(.plain)
                .font(.body)
            if !app.searchText.isEmpty {
                Button {
                    app.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
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
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning…")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .listRowSeparator(.hidden)
            }

            if app.orderedProjectNames.isEmpty, !app.isScanning {
                ContentUnavailableView {
                    Label("No documents", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text(app.searchText.isEmpty
                         ? "Scan Cursor projects or add a folder."
                         : "Nothing matches “\(app.searchText)”.")
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            } else {
                ForEach(app.orderedProjectNames, id: \.self) { projectName in
                    ProjectSection(projectName: projectName)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        // Force List rebuild when scan results arrive (macOS can skip updates
        // after the first async library populate).
        .id(app.libraryEpoch)
    }

    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "books.vertical")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(footerLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if app.filter != .all {
                Text(app.filter.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var footerLabel: String {
        let n = app.filteredDocuments.count
        let total = app.documents.count
        if app.searchText.isEmpty, app.filter == .all {
            return "\(total) document\(total == 1 ? "" : "s")"
        }
        return "\(n) of \(total)"
    }
}

// MARK: - Project section

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
            HStack(spacing: 7) {
                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                    .frame(width: 14)
                Text(projectName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(fileCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.05), in: Capsule())
            }
        }
    }
}

// MARK: - Tree nodes

private struct TreeNodeView: View {
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
            HStack(spacing: 7) {
                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(Color.secondary.opacity(0.85))
                    .frame(width: 14)
                Text(name)
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(fileCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.quaternary)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(doc.kind == .canvas ? Color.purple : Color.blue)
                .frame(width: 16)

            Text(doc.displayTitle)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            Text(Self.relativeFormatter.localizedString(for: doc.modifiedAt, relativeTo: Date()))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityLabel("\(doc.displayTitle), \(doc.kind.title)")
        .help(doc.relativePath == doc.fileName ? doc.urlPath : "\(doc.projectName)/\(doc.relativePath)")
    }
}
