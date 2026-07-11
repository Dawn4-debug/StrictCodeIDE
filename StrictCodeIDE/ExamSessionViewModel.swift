import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

/// Coordinates a full exam session: the "clear the editor first" safety
/// flow, a countdown timer, a compile-attempt cap, periodic autosave, and
/// exporting the final submission (code + violation log) when the session
/// ends. Wraps ExamModeManager, which stays focused purely on the
/// macOS-level lockdown mechanics (fullscreen, event tap, app-switch
/// detection).
final class ExamSessionViewModel: ObservableObject {
    @Published var showStartConfirmation: Bool = false
    @Published var durationMinutes: Int = 30
    @Published var maxCompileAttempts: Int = 10
    @Published var timeRemaining: TimeInterval = 0
    @Published var compileAttemptsUsed: Int = 0
    @Published var lastAutosaveAt: Date? = nil

    let examMode = ExamModeManager()

    private var objectChangeForwarder: AnyCancellable?
    private var countdownTimer: Timer?
    private var autosaveTimer: Timer?
    
    // 💡 CRITICAL FIX: Changed from 'weak' to a strong reference.
    // This stops the editor from being dropped out of memory during
    // fullscreen view layout refreshes or Escape key presses.
    private var activeEditor: EditorViewModel?
    private var autosaveURL: URL?

    var isActive: Bool { examMode.isActive }
    var violationLog: [String] { examMode.violationLog }
    var attemptsRemaining: Int { max(0, maxCompileAttempts - compileAttemptsUsed) }
    var canCompile: Bool { !isActive || attemptsRemaining > 0 }

    var timeRemainingFormatted: String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// "Saved just now" / "Saved 12s ago" / "Saved 3m ago" — this is what
    /// actually removes the "is it saving?" panic, far more than a raw
    /// timestamp does. Re-evaluated every second for free: this view model
    /// already publishes `timeRemaining` on a 1-second timer while a
    /// session is active, so anything reading this alongside the countdown
    /// redraws in step with it automatically.
    var autosaveRelativeLabel: String? {
        guard let savedAt = lastAutosaveAt else { return nil }
        let elapsed = Int(Date().timeIntervalSince(savedAt))
        switch elapsed {
        case ..<3: return "Saved just now"
        case ..<60: return "Saved \(elapsed)s ago"
        default: return "Saved \(elapsed / 60)m ago"
        }
    }

    init() {
        objectChangeForwarder = examMode.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Start / stop

    func requestStart() {
        showStartConfirmation = true
    }

    func confirmStart(editor: EditorViewModel) {
        editor.resetToTemplate()
        activeEditor = editor
        compileAttemptsUsed = 0
        timeRemaining = TimeInterval(durationMinutes * 60)
        autosaveURL = makeAutosaveURL(language: editor.selectedLanguage)

        // Closes a real loophole: a student could copy a solution from a
        // browser, launch the app, and paste it in before Exam Mode's
        // paste-blocking has anything to do with it. Clearing the
        // pasteboard the instant a session starts means whatever's on it
        // is gone before the student ever gets a chance to use it.
        NSPasteboard.general.clearContents()

        examMode.startExamMode()
        startCountdown()
        startAutosave()
    }

    func stopAndExport(editor: EditorViewModel) {
        finishSession(editor: editor, reason: "Manually ended by student")
    }

    private func finishSession(editor: EditorViewModel, reason: String) {
        countdownTimer?.invalidate()
        autosaveTimer?.invalidate()
        countdownTimer = nil
        autosaveTimer = nil

        examMode.stopExamMode()
        
        // Wait 0.4 seconds for window decorations and system bar transitions
        // to settle perfectly before prompting the export dialog sheet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self else { return }
            self.exportSubmission(editor: editor, endReason: reason)
        }
    }

    // MARK: - Compile attempt cap

    func recordCompileAttempt() -> Bool {
        guard isActive else { return true }
        guard attemptsRemaining > 0 else {
            examMode.violationLog.append("🚫 Compile blocked — attempt limit (\(maxCompileAttempts)) reached")
            return false
        }
        compileAttemptsUsed += 1
        return true
    }

    // MARK: - Countdown timer

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.timeRemaining -= 1
            if self.timeRemaining <= 0, let editor = self.activeEditor {
                self.finishSession(editor: editor, reason: "Time expired")
            }
        }
    }

    // MARK: - Autosave

    private func startAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.performAutosave()
        }
    }

    private func performAutosave() {
        guard let editor = activeEditor, let url = autosaveURL else { return }
        try? editor.sourceCode.write(to: url, atomically: true, encoding: .utf8)
        lastAutosaveAt = Date()
    }

    private func makeAutosaveURL(language: SupportedLanguage) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("StrictCodeIDE-AutoSave")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let timestamp = Int(Date().timeIntervalSince1970)
        return dir.appendingPathComponent("autosave-\(timestamp).\(language.sourceExtension)")
    }

    // MARK: - Submission export

    private func exportSubmission(editor: EditorViewModel, endReason: String) {
        let log = examMode.violationLog
        var report = """
        STRICT CODE IDE — EXAM SUBMISSION
        ==================================
        Language: \(editor.selectedLanguage.rawValue)
        Ended: \(endReason)
        Compile attempts used: \(compileAttemptsUsed) / \(maxCompileAttempts)
        Session violations logged: \(log.count)

        --- VIOLATION LOG ---
        """
        report += log.isEmpty ? "\n(none)" : "\n" + log.joined(separator: "\n")
        report += "\n\n--- SUBMITTED CODE ---\n\n\(editor.sourceCode)\n"

        let timestamp = Int(Date().timeIntervalSince1970)
        
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: { $0.canBecomeKey && $0.isVisible }) else { return }
            
            // 💡 FIXED: Brought back the explicit save prompt panel
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.plainText]
            savePanel.nameFieldStringValue = "exam-submission-\(timestamp).txt"
            savePanel.prompt = "Export"
            savePanel.title = "Save Exam Submission"
            
            // 💡 FIXED: Presented as a sheet modal so it anchors beautifully below the title bar
            savePanel.beginSheetModal(for: window) { response in
                if response == .OK, let url = savePanel.url {
                    try? report.write(to: url, atomically: true, encoding: .utf8)
                }
                
                // Forces main keyboard input focus directly back onto the code field layout canvas
                DispatchQueue.main.async {
                    if let contentView = window.contentView {
                        func findTextView(in view: NSView) -> NSTextView? {
                            if let tv = view as? NSTextView { return tv }
                            for subview in view.subviews {
                                if let found = findTextView(in: subview) { return found }
                            }
                            return nil
                        }
                        if let textView = findTextView(in: contentView) {
                            window.makeFirstResponder(textView)
                        }
                    }
                }
            }
        }
    }
}
