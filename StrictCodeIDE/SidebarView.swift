import SwiftUI
import AppKit

/// The project sidebar — Xcode's Navigator, scoped down to what a student
/// actually needs: browse a folder, open a file by clicking it, and
/// create/rename/delete files without leaving the app. Talks to
/// `ProjectViewModel` for all file-system state and reports file taps
/// upward via `onSelectFile` rather than opening files itself, so
/// ContentView stays the one place that decides what happens to unsaved
/// editor changes.
struct SidebarView: View {
    @ObservedObject var project: ProjectViewModel
    let selectedURL: URL?
    let onSelectFile: (URL) -> Void
    var disabled: Bool = false

    @State private var showNewItemSheet = false
    @State private var newItemIsFolder = false
    @State private var newItemParent: FileNode?
    @State private var newItemName = ""

    @State private var showRenameSheet = false
    @State private var renamingNode: FileNode?
    @State private var renameText = ""

    @State private var nodePendingDelete: FileNode?
    @State private var projectError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let root = project.rootNode {
                List {
                    OutlineGroup(root.children ?? [], id: \.url, children: \.children) { node in
                        row(for: node)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            } else {
                emptyState
            }
        }
        .disabled(disabled)
        // `.disabled()` only gates real SwiftUI controls (Button, Picker,
        // Menu, ...) that read `@Environment(\.isEnabled)` — it does NOT
        // stop a raw `.onTapGesture`, which is what actually opens a file
        // below. Without this, the sidebar *looked* locked during Exam
        // Mode but tapping a file row still worked, letting someone load a
        // file written elsewhere straight into the editor — a full
        // end-run around the paste block. `allowsHitTesting` is the
        // blanket fix: it stops every gesture in the subtree, tap
        // included, not just the ones attached to a Control.
        .allowsHitTesting(!disabled)
        .appGlass()
        .alert(newItemIsFolder ? "New Folder" : "New File", isPresented: $showNewItemSheet) {
            TextField("Name", text: $newItemName)
            Button("Create") { confirmNewItem() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(newItemIsFolder
                 ? "Enter a name for the new folder."
                 : "Enter a file name, including its extension (e.g. main.c).")
        }
        .alert("Rename", isPresented: $showRenameSheet) {
            TextField("Name", text: $renameText)
            Button("Rename") { confirmRename() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a new name for \"\(renamingNode?.name ?? "")\".")
        }
        .confirmationDialog(
            "Move \"\(nodePendingDelete?.name ?? "")\" to the Trash?",
            isPresented: Binding(
                get: { nodePendingDelete != nil },
                set: { if !$0 { nodePendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { nodePendingDelete = nil }
        } message: {
            Text(nodePendingDelete?.isDirectory == true
                 ? "This folder and everything inside it will be moved to the Trash."
                 : "This file will be moved to the Trash.")
        }
        .alert("Couldn't Complete That", isPresented: Binding(
            get: { projectError != nil },
            set: { if !$0 { projectError = nil } }
        )) {
            Button("OK", role: .cancel) { projectError = nil }
        } message: {
            Text(projectError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundColor(.accentColor)
            Text(project.isProjectOpen ? project.projectName : "No Project")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer()
            if project.isProjectOpen {
                Menu {
                    Button("New File...") {
                        guard let root = project.rootNode else { return }
                        beginCreatingItem(in: root, isFolder: false)
                    }
                    Button("New Folder...") {
                        guard let root = project.rootNode else { return }
                        beginCreatingItem(in: root, isFolder: true)
                    }
                    Divider()
                    Button("Reveal Project in Finder") {
                        guard let url = project.rootURL else { return }
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Button("Refresh") { project.refresh() }
                    Divider()
                    Button("Close Project") { project.closeProject() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 20)
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 30))
                .foregroundColor(.secondary)
            Text("No Project Open")
                .font(.headline)
            Text("Open a folder to browse, create, and edit its files as a project.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
            Button("Open Folder...") { project.openFolderPicker() }
                .buttonStyle(.glassProminent)

            if !project.recentProjects.isEmpty {
                Divider().padding(.top, 6).padding(.horizontal, 18)
                Text("RECENT PROJECTS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)

                VStack(spacing: 0) {
                    ForEach(project.recentProjects) { recent in
                        recentProjectRow(recent)
                    }
                }
            }
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
    }

    private func recentProjectRow(_ recent: RecentProject) -> some View {
        Button {
            project.openProject(at: recent.url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(recent.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Text(recent.path)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove from Recents") { project.forgetRecentProject(recent) }
        }
    }

    // MARK: - Tree rows

    private func row(for node: FileNode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: node.isDirectory ? "folder.fill" : icon(for: node))
                .foregroundColor(node.isDirectory ? .accentColor : .secondary)
                .frame(width: 14)
            Text(node.name)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(selectedURL == node.url ? XcodeTheme.selectionColor : Color.clear)
        )
        .onTapGesture {
            // Belt-and-suspenders: even though the parent view already
            // blocks this via `allowsHitTesting`, checking `disabled` here
            // too means this row can never open a file while locked, even
            // if it's ever reused somewhere that guard isn't applied.
            guard !disabled, !node.isDirectory else { return }
            onSelectFile(node.url)
        }
        .contextMenu {
            if node.isDirectory {
                Button("New File...") { beginCreatingItem(in: node, isFolder: false) }
                Button("New Folder...") { beginCreatingItem(in: node, isFolder: true) }
                Divider()
            }
            Button("Rename...") { beginRenaming(node) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
            Divider()
            Button("Delete", role: .destructive) { nodePendingDelete = node }
        }
    }

    private func icon(for node: FileNode) -> String {
        let sourceExtensions: Set<String> = ["c", "h", "cpp", "hpp", "cc", "java"]
        return sourceExtensions.contains(node.url.pathExtension.lowercased()) ? "doc.text.fill" : "doc"
    }

    // MARK: - Actions

    private func beginCreatingItem(in parent: FileNode, isFolder: Bool) {
        newItemParent = parent
        newItemIsFolder = isFolder
        newItemName = ""
        showNewItemSheet = true
    }

    private func confirmNewItem() {
        guard let parent = newItemParent else { return }
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            if newItemIsFolder {
                try project.createFolder(named: name, in: parent)
            } else {
                try project.createFile(named: name, in: parent)
            }
        } catch {
            projectError = error.localizedDescription
        }
    }

    private func beginRenaming(_ node: FileNode) {
        renamingNode = node
        renameText = node.name
        showRenameSheet = true
    }

    private func confirmRename() {
        guard let node = renamingNode else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != node.name else { return }
        do {
            try project.rename(node, to: name)
        } catch {
            projectError = error.localizedDescription
        }
    }

    private func confirmDelete() {
        guard let node = nodePendingDelete else { return }
        do {
            try project.delete(node)
        } catch {
            projectError = error.localizedDescription
        }
        nodePendingDelete = nil
    }
}
