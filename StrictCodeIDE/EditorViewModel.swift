import Foundation
import Combine

/// Cursor line/column, split out from `EditorViewModel` into its own tiny
/// `ObservableObject` on purpose. Cursor position changes on essentially
/// every keystroke and every arrow-key press — if it lived on
/// `EditorViewModel` as a `@Published` property (as `sourceCode` and
/// everything else does), every one of those changes would fire that
/// object's `objectWillChange` and force `ContentView`'s entire body —
/// toolbar, sidebar, tab bar, editor — to re-evaluate along with it. Kept
/// separate, only the small status-bar label that actually observes this
/// object re-renders.
final class CursorPositionModel: ObservableObject {
    @Published var line: Int = 1
    @Published var column: Int = 1
}

/// Owns everything related to "what's in the editor and what happens when
/// you run it" — source code, selected language, indentation, compile
/// output, and the current file on disk. ContentView reads/writes this
/// instead of holding the state itself.
final class EditorViewModel: ObservableObject {
    @Published var sourceCode: String = "" {
        didSet {
            isDirty = sourceCode != lastPersistedSnapshot
            // Once the student edits code, line numbers from the last
            // compile may no longer line up with anything — stale
            // squiggles pointing at the wrong line are worse than none.
            if !diagnostics.isEmpty {
                diagnostics = []
            }
        }
    }
    /// Whether `sourceCode` differs from what's on disk (or, for a
    /// never-saved buffer, from its last "committed" state). Lets the UI
    /// show a small unsaved-changes indicator and guard against silently
    /// discarding edits when switching files in the project sidebar.
    @Published private(set) var isDirty: Bool = false
    private var lastPersistedSnapshot: String = ""
    
    @Published var selectedLanguage: SupportedLanguage = .c
    
    @Published var indentWidth: Int = 4
    @Published var output: String = "Output will appear here."
    @Published var isCompiling: Bool = false
    @Published var currentFileURL: URL? = nil
    /// See `CursorPositionModel` above for why this isn't `@Published`
    /// directly on `EditorViewModel`.
    let cursorPosition = CursorPositionModel()
    @Published var lastBuildStatus: BuildStatus = .none
    @Published var complexityNotes: String = ""
    @Published var testCases: [TestCase] = []
    @Published var testResults: [TestCaseResult] = []
    @Published var isRunningTests: Bool = false
    /// Files currently open as tabs, in tab-bar order. `TabBarView` reads
    /// this directly; `openFile(at:)`/`loadFile(url:)`/`closeTab(url:)` are
    /// the only places that mutate it.
    @Published private(set) var openTabs: [URL] = []
    /// Errors/warnings from the most recent compile, keyed by source line.
    /// Consumed by `CodeEditorView` to draw inline squiggles and gutter
    /// badges next to the broken line.
    @Published var diagnostics: [CompileDiagnostic] = []
    /// Unsaved edits for tabs that aren't currently active, keyed by file
    /// URL, so switching tabs never silently discards work the way a
    /// single-buffer editor would.
    private var tabBuffers: [URL: String] = [:]

    enum BuildStatus {
        case none, success, failure

        var label: String {
            switch self {
            case .none: return "Not built"
            case .success: return "Build succeeded"
            case .failure: return "Build failed"
            }
        }

        var systemImage: String {
            switch self {
            case .none: return "circle"
            case .success: return "checkmark.circle.fill"
            case .failure: return "xmark.circle.fill"
            }
        }
    }

    private let compilerService = CompilerRunner()

    var displayFileName: String {
        currentFileURL?.lastPathComponent ?? "Untitled.\(selectedLanguage.sourceExtension)"
    }

    var lineCount: Int {
        sourceCode.components(separatedBy: "\n").count
    }

    init() {
        sourceCode = templateForLanguage(selectedLanguage)
        markPersisted()
    }

    func resetToTemplate() {
        sourceCode = templateForLanguage(selectedLanguage)
        output = "Output will appear here."
        currentFileURL = nil
        complexityNotes = ""
        testCases = []
        testResults = []
        lastBuildStatus = .none
        diagnostics = []
        openTabs = []
        tabBuffers = [:]
        markPersisted()
    }

    // MARK: - Tabs

    /// Loads a file straight from disk into the editor and adds it as a tab
    /// if it isn't already open — used when the project sidebar is tapped.
    /// Distinct from `open()` below, which shows an NSOpenPanel; here the
    /// URL is already known. Switching to a file that's already open just
    /// activates its existing tab via `loadFile(url:)`.
    func openFile(at url: URL) {
        if !openTabs.contains(url) {
            openTabs.append(url)
        }
        loadFile(url: url)
    }

    /// Activates an already-open tab, restoring whatever unsaved edits it
    /// had before we switched away from it. Also used internally by
    /// `openFile(at:)` for first-time opens.
    func loadFile(url: URL) {
        guard currentFileURL != url else { return }

        // Stash whatever's in the buffer we're leaving so it isn't lost.
        if let leaving = currentFileURL {
            tabBuffers[leaving] = sourceCode
        }

        guard let onDiskContents = try? String(contentsOf: url, encoding: .utf8) else {
            output = "⚠️ Couldn't open \(url.lastPathComponent)."
            return
        }
        let contents = tabBuffers[url] ?? onDiskContents

        if let language = SupportedLanguage.allCases.first(where: { $0.sourceExtension == url.pathExtension.lowercased() }),
           language != selectedLanguage {
            selectedLanguage = language // triggers resetToTemplate; overwritten below
        }

        lastPersistedSnapshot = onDiskContents
        sourceCode = contents
        currentFileURL = url
        output = "Output will appear here."
        lastBuildStatus = .none
        complexityNotes = ""
        testCases = []
        testResults = []
        diagnostics = []
        isDirty = (contents != onDiskContents)
    }

    /// Closes a tab. If it was the active tab, activates the next-best tab
    /// (the one that took its place, or the previous one, or — if it was
    /// the last tab — falls back to a blank template).
    func closeTab(url: URL) {
        tabBuffers.removeValue(forKey: url)
        guard let index = openTabs.firstIndex(of: url) else { return }
        openTabs.remove(at: index)

        guard currentFileURL == url else { return }

        if index < openTabs.count {
            currentFileURL = nil // so loadFile doesn't early-return
            loadFile(url: openTabs[index])
        } else if let last = openTabs.last {
            currentFileURL = nil
            loadFile(url: last)
        } else {
            sourceCode = templateForLanguage(selectedLanguage)
            output = "Output will appear here."
            currentFileURL = nil
            complexityNotes = ""
            testCases = []
            testResults = []
            lastBuildStatus = .none
            diagnostics = []
            markPersisted()
        }
    }

    private func markPersisted() {
        lastPersistedSnapshot = sourceCode
        isDirty = false
    }

    func compile() {
        isCompiling = true
        output = "Compiling..."
        diagnostics = []
        compilerService.compileAndRun(code: sourceCode, language: selectedLanguage) { [weak self] result in
            DispatchQueue.main.async {
                self?.output = result
                self?.isCompiling = false
                self?.lastBuildStatus = result.hasPrefix("❌") ? .failure : .success
                self?.diagnostics = DiagnosticParser.parse(result)
            }
        }
    }

    func updateCursorPosition(line: Int, column: Int) {
        cursorPosition.line = line
        cursorPosition.column = column
    }

    // MARK: - Test cases

    func addTestCase() {
        testCases.append(TestCase(name: "Test \(testCases.count + 1)", input: "", expectedOutput: ""))
    }

    func removeTestCase(id: UUID) {
        testCases.removeAll { $0.id == id }
    }

    func updateTestCase(id: UUID, input: String) {
        guard let index = testCases.firstIndex(where: { $0.id == id }) else { return }
        testCases[index].input = input
    }

    func updateTestCase(id: UUID, expectedOutput: String) {
        guard let index = testCases.firstIndex(where: { $0.id == id }) else { return }
        testCases[index].expectedOutput = expectedOutput
    }

    func runTestCases() {
        guard !testCases.isEmpty else { return }
        isRunningTests = true
        testResults = []
        compilerService.runTestCases(code: sourceCode, language: selectedLanguage, testCases: testCases) { [weak self] results in
            DispatchQueue.main.async {
                self?.testResults = results
                self?.isRunningTests = false
            }
        }
    }

    func save(completion: ((URL?) -> Void)? = nil) {
        FileManagerHelper.save(code: sourceCode, language: selectedLanguage, currentURL: currentFileURL) { [weak self] url in
            if let url = url {
                self?.currentFileURL = url
                self?.tabBuffers.removeValue(forKey: url) // buffer now matches disk
                if let self = self, !self.openTabs.contains(url) {
                    self.openTabs.append(url)
                }
                self?.markPersisted()
            }
            completion?(url)
        }
    }

    func open() {
        FileManagerHelper.open { [weak self] contents, url in
            guard let self = self, let contents = contents, let url = url else { return }
            if let current = self.currentFileURL {
                self.tabBuffers[current] = self.sourceCode
            }
            if !self.openTabs.contains(url) {
                self.openTabs.append(url)
            }
            self.sourceCode = contents
            self.currentFileURL = url
            self.markPersisted()
        }
    }

    private func templateForLanguage(_ language: SupportedLanguage) -> String {
        switch language {
        case .c:
            return "#include <stdio.h>\n\nint main() {\n    printf(\"Hello, student!\\n\");\n    return 0;\n}"
        case .cpp:
            return "#include <iostream>\n\nint main() {\n    std::cout << \"Hello, student!\" << std::endl;\n    return 0;\n}"
        case .java:
            return "public class Main {\n    public static void main(String[] args) {\n        System.out.println(\"Hello, student!\");\n    }\n}"
        }
    }
}
