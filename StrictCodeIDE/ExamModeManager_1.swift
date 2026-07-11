import Cocoa
import Combine

/// Coordinates "exam mode": fullscreen kiosk lock, detecting when the
/// student switches to another app, and blocking system-level shortcuts
/// (Cmd+Tab, Cmd+Space/Spotlight, Cmd+H, Cmd+Q) while a session is active.
final class ExamModeManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var violationLog: [String] = []

    var disableCopyPaste: Bool {
        UserDefaults.standard.bool(forKey: "exam_disableCopyPaste")
    }
    var disableNewTabs: Bool {
        UserDefaults.standard.bool(forKey: "exam_disableNewTabs")
    }
    var requireFullscreen: Bool {
        UserDefaults.standard.bool(forKey: "exam_requireFullscreen")
    }
    var confirmBeforeExit: Bool {
        UserDefaults.standard.object(forKey: "exam_confirmBeforeExit") as? Bool ?? true
    }
    
    static weak var activeInstance: ExamModeManager?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var appActivationObserver: NSObjectProtocol?
    private var previousPresentationOptions: NSApplication.PresentationOptions = []

    private var frameBeforeKiosk: NSRect?
    private var previousStyleMask: NSWindow.StyleMask = []
    private var wasNativeFullScreenAtStart: Bool = false

    // MARK: - Permission

    static func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Start / stop

    func startExamMode() {
        guard !isActive else { return }
        guard ExamModeManager.hasAccessibilityPermission else {
            violationLog.append("❌ Cannot start: Accessibility permission not granted. Go to System Settings > Privacy & Security > Accessibility.")
            return
        }
        isActive = true
        violationLog.removeAll()
        ExamModeManager.activeInstance = self

        enterKioskMode()
        startWatchingAppSwitches()
        startBlockingSystemShortcuts()
    }

    func stopExamMode() {
        guard isActive else { return }
        isActive = false
        if ExamModeManager.activeInstance === self {
            ExamModeManager.activeInstance = nil
        }

        stopBlockingSystemShortcuts()
        stopWatchingAppSwitches()
        
        exitKioskMode()
    }

    func emergencyShutdown() {
        stopExamMode()
    }

    // MARK: - Fullscreen / kiosk mode

    private func enterKioskMode() {
        guard let window = NSApplication.shared.windows.first(where: { $0.canBecomeKey && $0.isVisible }) else { return }

        previousPresentationOptions = NSApplication.shared.presentationOptions
        frameBeforeKiosk = window.frame
        previousStyleMask = window.styleMask

        // 🔑 If the window is already in macOS's *native* full screen (the green
        // traffic-light button / Cmd+Ctrl+F), AppKit owns its styleMask while the
        // window lives in that dedicated fullscreen Space. Forcibly overwriting
        // styleMask/frame in that state (as the code below does for the normal
        // case) throws NSInternalInconsistencyException and crashes the app.
        // So: if we're already native-fullscreen, don't touch styleMask/frame at
        // all — the window already covers the whole screen and the menu bar/dock
        // are already hidden by the system. Just apply the presentation option
        // locks (which are safe to set in this state).
        wasNativeFullScreenAtStart = window.styleMask.contains(.fullScreen)

        DispatchQueue.main.async {
            NSApplication.shared.presentationOptions = [.hideDock, .hideMenuBar, .disableForceQuit, .disableProcessSwitching]

            guard !self.wasNativeFullScreenAtStart else {
                window.makeKeyAndOrderFront(nil)
                return
            }

            window.styleMask = [.borderless]

            if let screen = window.screen ?? NSScreen.main {
                window.setFrame(screen.visibleFrame, display: true, animate: false)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func exitKioskMode() {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }) else {
            frameBeforeKiosk = nil
            return
        }
        
        let targetOptions = previousPresentationOptions
        let targetStyle = previousStyleMask
        let targetFrame = frameBeforeKiosk // 💡 Capture original window layout footprint
        let wasNativeFullScreen = wasNativeFullScreenAtStart

        DispatchQueue.main.async {
            // 1. Restore standard OS Dock and Menu Bar presentation states
            NSApplication.shared.presentationOptions = targetOptions

            // 🔑 If we entered exam mode while the window was already in native
            // macOS full screen, we never touched styleMask/frame on the way in
            // (see enterKioskMode), so we must not touch them on the way out
            // either — the window is still safely in its native fullscreen
            // Space and forcing styleMask/setFrame here would crash for the
            // same reason it did on entry.
            guard !wasNativeFullScreen else {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                return
            }

            // 2. Return normal window frames (Title bar, Close, Minimize, Zoom controls)
            window.styleMask = targetStyle
            window.contentView?.needsLayout = true
            
            // 💡 3. FIXED: Animate window frame back to its original pre-exam size and coordinates!
            if let restoreFrame = targetFrame {
                window.setFrame(restoreFrame, display: true, animate: true)
            } else if let screen = window.screen ?? NSScreen.main {
                window.setFrame(screen.visibleFrame, display: true, animate: true)
            }
            
            // 4. Solidify focus context
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        
        frameBeforeKiosk = nil
        wasNativeFullScreenAtStart = false
    }

    // MARK: - App switch detection

    private func startWatchingAppSwitches() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                let entry = "⚠️ Switched to \(app.localizedName ?? "another app") at \(Self.timestamp())"
                self.violationLog.append(entry)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func stopWatchingAppSwitches() {
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }
    }

    // MARK: - Global shortcut blocking

    private func startBlockingSystemShortcuts() {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<ExamModeManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handleEvent(type: type, event: event)
            },
            userInfo: selfPtr
        )

        guard let eventTap = eventTap else {
            violationLog.append("❌ Failed to create event tap — check Accessibility permission.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func stopBlockingSystemShortcuts() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private static let blockedKeyCodes: Set<Int64> = [48, 49, 4, 12]

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isActive else { return Unmanaged.passUnretained(event) }

        let isCommandDown = event.flags.contains(.maskCommand)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if isCommandDown && Self.blockedKeyCodes.contains(keyCode) {
            let entry = "🚫 Blocked shortcut attempt (keyCode \(keyCode)) at \(Self.timestamp())"
            DispatchQueue.main.async {
                self.violationLog.append(entry)
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
