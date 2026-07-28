//
//  LibrarySidebar.swift
//  Canvas Library
//
//  Plain column layout (not NavigationSplitView-owned List). HSplitView parents
//  this view so content stays inside the window safe area under the toolbar.
//

import AppKit
import SwiftUI

struct LibrarySidebar: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let projectNames = displayedProjectNames
        let scanning = app.isScanning
        let epoch = app.libraryEpoch

        VStack(spacing: 0) {
            searchField
            kindFilter
            Divider()
            documentList(projectNames: projectNames, scanning: scanning, epoch: epoch)
            Divider()
            sidebarFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            app.ensureLibraryLoaded()
        }
        .onChange(of: app.selectedID) { _, _ in
            app.expandProjectForSelection()
        }
        .onChange(of: app.searchText) { _, query in
            guard !query.isEmpty else { return }
            var next = app.expandedProjects
            next.formUnion(app.sidebarProjectNames)
            app.expandedProjects = next
        }
        .onChange(of: app.libraryEpoch) { _, _ in
            if app.expandedProjects.isEmpty, !app.sidebarProjectNames.isEmpty {
                app.expandedProjects = Set(app.sidebarProjectNames)
            }
        }
    }

    private var displayedProjectNames: [String] {
        if !app.searchText.isEmpty || app.filter != .all {
            return app.orderedProjectNames
        }
        return app.sidebarProjectNames
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search library", text: $app.searchText)
                .textFieldStyle(.plain)
                .font(.body)
                .accessibilityLabel("Search library")
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
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// Both | Canvases | Markdown — primary kind switch for Cursor-style working docs.
    private var kindFilter: some View {
        Picker("Show", selection: $app.filter) {
            ForEach(LibraryFilter.allCases) { f in
                Text(f.title).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .help("Show canvases, markdown, or both")
    }

    @ViewBuilder
    private func documentList(projectNames: [String], scanning: Bool, epoch: UInt64) -> some View {
        List(selection: Binding(
            get: { app.selectedID },
            set: { newID in
                if let newID, let doc = app.filteredDocuments.first(where: { $0.id == newID }) {
                    app.select(doc)
                } else if newID == nil {
                    app.selectedID = nil
                }
            }
        )) {
            if scanning && projectNames.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning…")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .listRowSeparator(.hidden)
            } else if projectNames.isEmpty {
                ContentUnavailableView {
                    Label("No documents", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text(emptyDescription)
                }
                .listRowSeparator(.hidden)
            } else {
                ForEach(projectNames, id: \.self) { projectName in
                    ProjectSection(projectName: projectName)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(nil, value: epoch)
    }

    private var emptyDescription: String {
        if !app.searchText.isEmpty {
            return "Nothing matches “\(app.searchText)”."
        }
        if !app.hiddenProjects.isEmpty || !app.excludedFolders.isEmpty {
            return "Everything is hidden, filtered, or empty. Check Settings → Library."
        }
        if app.spaces.isEmpty {
            return "Add a folder from the toolbar or Settings to build your library."
        }
        return "No matching documents in your folders."
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var footerLabel: String {
        let n = app.filteredDocuments.count
        if app.isScanning, app.documents.isEmpty {
            return "Scanning…"
        }
        if app.searchText.isEmpty, app.filter == .all {
            return "\(n) document\(n == 1 ? "" : "s")"
        }
        let total = app.documents.filter { !app.hiddenProjects.contains($0.projectName) }.count
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

    private var names: [String] {
        if !app.searchText.isEmpty || app.filter != .all {
            return app.orderedProjectNames
        }
        return app.sidebarProjectNames
    }

    private var isExpandedBinding: Binding<Bool> {
        Binding(
            get: {
                if !app.searchText.isEmpty { return true }
                if app.expandedProjects.isEmpty { return true }
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
        .contextMenu {
            Button {
                app.moveProject(projectName, direction: -1)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(names.first == projectName)

            Button {
                app.moveProject(projectName, direction: 1)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(names.last == projectName)

            Divider()

            Button {
                app.revealProjectInFinder(projectName)
            } label: {
                Label("Reveal in Finder", systemImage: "finder")
            }

            Button {
                app.hideProject(projectName)
            } label: {
                Label("Hide Project", systemImage: "eye.slash")
            }

            if let space = app.removableSpace(forProject: projectName) {
                Divider()
                Button(role: .destructive) {
                    app.removeSpace(space)
                } label: {
                    Label("Remove Folder from Library", systemImage: "folder.badge.minus")
                }
            }
        }
    }
}

// MARK: - Tree nodes

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
            DocumentRow(
                doc: doc,
                isUnsaved: app.hasUnsavedEdits(forDocumentID: doc.id),
                gitStatus: app.gitStatus(forDocumentID: doc.id)
            )
                .tag(doc.id)
                .contextMenu {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([doc.url])
                    } label: {
                        Label("Reveal in Finder", systemImage: "finder")
                    }
                }
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
            get: {
                if !app.searchText.isEmpty { return true }
                return app.isFolderExpanded(project: projectName, folderPath: relativePath)
            },
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
        .contextMenu {
            Button {
                app.revealFolderInFinder(project: projectName, folderPath: relativePath)
            } label: {
                Label("Reveal in Finder", systemImage: "finder")
            }

            Button {
                app.excludeFolder(project: projectName, folderPath: relativePath)
            } label: {
                Label("Hide Folder", systemImage: "eye.slash")
            }
        }
    }
}

// MARK: - Document row

private struct DocumentRow: View {
    let doc: WorkingDocument
    var isUnsaved: Bool = false
    var gitStatus: GitFileStatus? = nil

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var isGitChanged: Bool { gitStatus?.isChanged == true }

    private var badgeColor: Color {
        guard let gitStatus else { return .secondary }
        if gitStatus.isUntracked { return .green }
        if gitStatus.isStaged && !gitStatus.hasWorkTreeChanges { return .indigo }
        return .orange
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: doc.kind.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(doc.kind == .canvas ? Color.purple : Color.blue)
                .frame(width: 16)

            Text(doc.displayTitle)
                .font(.callout.weight((isUnsaved || isGitChanged) ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            // Priority: unsaved buffer → orange dot; else git letter; else relative date.
            if isUnsaved {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                    .help(isGitChanged
                          ? "Unsaved changes (also \(gitStatus?.capsuleTitle ?? "modified") in git)"
                          : "Unsaved changes")
                    .accessibilityLabel("Unsaved")
            } else if let badge = gitStatus?.sidebarBadge {
                Text(badge)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(badgeColor)
                    .frame(minWidth: 12, alignment: .trailing)
                    .help(gitStatus?.sidebarHelp ?? "Git changes")
                    .accessibilityLabel(gitStatus?.capsuleTitle ?? "Modified")
            } else {
                Text(Self.relativeFormatter.localizedString(for: doc.modifiedAt, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel(accessibilityText)
        .help(doc.relativePath == doc.fileName ? doc.urlPath : "\(doc.projectName)/\(doc.relativePath)")
    }

    private var accessibilityText: String {
        var parts = ["\(doc.displayTitle), \(doc.kind.title)"]
        if isUnsaved { parts.append("unsaved") }
        if let label = gitStatus?.capsuleTitle { parts.append(label) }
        return parts.joined(separator: ", ")
    }
}
