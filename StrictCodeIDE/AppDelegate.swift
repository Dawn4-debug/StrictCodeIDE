import Cocoa

/// Exam Mode intentionally hides the dock and menu bar, disables force-quit,
/// and swallows Cmd+Tab / Cmd+Space / Cmd+H / Cmd+Q while a session is
/// active (see ExamModeManager). That's the whole point of a lockdown mode —
/// but it also means if the window closes or the app is asked to quit
/// without going through the normal "Exit Exam Mode" button, the lockdown
/// state never gets released. With no window, no dock icon, and no menu
/// bar, there is nothing left on screen to undo it from — that's the "the
/// computer gets stuck" bug. This delegate makes sure the lockdown is always
/// torn down before the window disappears or the app terminates.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.windows.first?.delegate = self
    }

    /// If the app is asked to quit (Cmd+Q reaching through some other path,
    /// AppleScript `quit`, Dock menu, etc.) while a session is active, drop
    /// the kiosk presentation options and remove the event tap first so
    /// whatever quits the app doesn't leave the Mac's dock/menu bar/shortcuts
    /// in a locked state with no process left to release them.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let exam = ExamModeManager.activeInstance, exam.isActive {
            exam.emergencyShutdown()
        }
        return .terminateNow
    }

    /// Closing the single window (red traffic-light button) doesn't normally
    /// quit a SwiftUI WindowGroup app — it just leaves the app running with
    /// no window. Combined with Exam Mode's hidden dock/menu bar, that means
    /// no way back in. So: release the lockdown first, tell the student a
    /// submission wasn't exported this way, and then let the app quit
    /// cleanly instead of lingering invisibly.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let exam = ExamModeManager.activeInstance, exam.isActive {
            exam.emergencyShutdown()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Exam Mode was force-closed"
            alert.informativeText = "The window closed while a session was still active, so the lockdown has been released but no submission was exported. Next time, use \"Exit Exam Mode\" in the toolbar to end a session properly."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
