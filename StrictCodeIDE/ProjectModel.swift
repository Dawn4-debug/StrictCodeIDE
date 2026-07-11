import Foundation
import Combine
/// A single entry in the project's file tree. Value type, rebuilt by
/// `ProjectViewModel.refresh()` whenever the folder changes on disk — there's
/// no attempt to diff/patch the tree in place, since student projects are
/// small and a full rescan is cheap and impossible to get subtly wrong.
struct FileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    /// `nil` for files. Directories always get at least `[]`, which is what
    /// tells OutlineGroup to draw a (possibly empty) disclosure triangle.
    var children: [FileNode]?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

enum ProjectError: LocalizedError {
    case alreadyExists
    case invalidName

    var errorDescription: String? {
        switch self {
        case .alreadyExists:
            return "A file or folder with that name already exists here."
        case .invalidName:
            return "That name isn't valid — it can't be empty or contain \"/\"."
        }
    }
}

/// Owns "the currently open project": which folder is open, its file tree,
/// and the handful of file-system operations a sidebar needs (create,
/// rename, delete). Deliberately knows nothing about the editor or what's
/// currently open in it — ContentView is what wires a sidebar tap to
/// `EditorViewModel.openFile(at:)`, keeping this class reusable if the app
/// ever gets a second sidebar-like surface.
final class ProjectViewModel: ObservableObject {
    @Published var rootURL: URL? {
            didSet {
                if let url = rootURL {
                    watcher.start(watching: url)
                } else {
                    watcher.stop()
                }
            }
        }
        
        @Published private(set) var rootNode: FileNode?
        @Published private(set) var recentProjects: [RecentProject] = []
        
        // 2. ADD THIS LINE: Put the watcher right here next to recentStore
        private let watcher = DirectoryWatcher()
        private let recentStore = RecentProjectsStore()
        
        /// Folder names that are almost never useful to show a student browsing...
    private static let ignoredNames: Set<String> = [
        ".git", ".build", ".swiftpm", ".vscode", ".idea",
        ".DS_Store", "DerivedData", "node_modules", "__pycache__"
    ]
    var isProjectOpen: Bool { rootURL != nil }
    var projectName: String { rootURL?.lastPathComponent ?? "" }

    init() {
        recentProjects = recentStore.load()
        watcher.onDirectoryChanged = { [weak self] in
            self?.scheduleRefresh()
        }
    }

    // MARK: - Opening / closing

    func openFolderPicker() {
        FileManagerHelper.openFolder { [weak self] url in
            guard let self, let url else { return }
            self.openProject(at: url)
        }
    }

    func openProject(at url: URL) {
        rootURL = url
        refresh()
        recentStore.addOrBumpToFront(url: url)
        recentProjects = recentStore.load()
    }

    func closeProject() {
        scanGeneration += 1
        refreshWorkItem?.cancel()
        rootURL = nil
        rootNode = nil
    }

    func forgetRecentProject(_ recent: RecentProject) {
        recentStore.remove(path: recent.path)
        recentProjects = recentStore.load()
    }

    // MARK: - Tree scanning

    private var refreshWorkItem: DispatchWorkItem?
    private var scanGeneration = 0
    private static let scanQueue = DispatchQueue(label: "com.strictcodeide.projectscan", qos: .userInitiated)

    /// Debounced entry point for filesystem-triggered rescans. A single save
    /// or a quick sequence of file operations can fire several watcher
    /// events in a row; without this, each one would kick off its own full
    /// recursive directory scan back to back. Coalescing into one scan
    /// ~150ms after the last event keeps that down to one.
    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    /// Rescans the project folder and republishes `rootNode`. The scan
    /// itself — recursive `FileManager` calls, real disk I/O — runs on a
    /// background queue so it never blocks the main thread (and therefore
    /// never stalls typing, scrolling, or anything else) even for larger
    /// student projects; only the final, already-built tree gets handed
    /// back to the main actor to publish.
    func refresh() {
        guard let rootURL else { return }
        scanGeneration += 1
        let generation = scanGeneration
        Self.scanQueue.async { [weak self] in
            let node = Self.scan(url: rootURL)
            DispatchQueue.main.async {
                guard let self, self.scanGeneration == generation else { return }
                self.rootNode = node
            }
        }
    }

    private static func scan(url: URL) -> FileNode {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard exists, isDir.boolValue else {
            return FileNode(url: url, isDirectory: false, children: nil)
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let children = contents
            .filter { !ignoredNames.contains($0.lastPathComponent) }
            .sorted { lhs, rhs in
                let lhsIsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let rhsIsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if lhsIsDir != rhsIsDir { return lhsIsDir && !rhsIsDir } // folders first
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .map { scan(url: $0) }

        return FileNode(url: url, isDirectory: true, children: children)
    }

    // MARK: - File operations

    func createFile(named name: String, in parent: FileNode) throws {
        try Self.validate(name: name)
        let url = parent.url.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectError.alreadyExists
        }
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
            throw ProjectError.invalidName
        }
        refresh()
    }

    func createFolder(named name: String, in parent: FileNode) throws {
        try Self.validate(name: name)
        let url = parent.url.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectError.alreadyExists
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        refresh()
    }

    func rename(_ node: FileNode, to newName: String) throws {
        try Self.validate(name: newName)
        let newURL = node.url.deletingLastPathComponent().appendingPathComponent(newName)
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            throw ProjectError.alreadyExists
        }
        try FileManager.default.moveItem(at: node.url, to: newURL)
        refresh()
    }

    /// Moves to the Trash rather than deleting outright — a student's whole
    /// project living inside a folder means one misclick shouldn't be
    /// unrecoverable the way it would be with a permanent delete.
    func delete(_ node: FileNode) throws {
        try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
        refresh()
    }

    private static func validate(name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            throw ProjectError.invalidName
        }
    }
}

// MARK: - Recent projects

struct RecentProject: Identifiable, Codable, Equatable {
    let path: String
    let name: String
    let lastOpened: Date

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
}

/// Persists recently opened project folders across launches. The app runs
/// without App Sandbox (see project build settings), so plain absolute
/// paths are stable and reusable — no security-scoped bookmarks needed.
final class RecentProjectsStore {
    private let key = "recentProjects"
    private let maxCount = 8

    func load() -> [RecentProject] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let list = try? JSONDecoder().decode([RecentProject].self, from: data)
        else { return [] }

        // Drop entries whose folder has since moved or been deleted, so the
        // list never promises access to something that's no longer there.
        let filtered = list.filter { FileManager.default.fileExists(atPath: $0.path) }
        if filtered.count != list.count { save(filtered) }
        return filtered
    }

    func addOrBumpToFront(url: URL) {
        var list = load()
        list.removeAll { $0.path == url.path }
        list.insert(RecentProject(path: url.path, name: url.lastPathComponent, lastOpened: Date()), at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        save(list)
    }

    func remove(path: String) {
        var list = load()
        list.removeAll { $0.path == path }
        save(list)
    }

    private func save(_ list: [RecentProject]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
