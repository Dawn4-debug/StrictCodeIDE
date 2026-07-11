import SwiftUI

struct ContentView: View {
    @StateObject private var editor = EditorViewModel()
    @StateObject private var exam = ExamSessionViewModel()
    @StateObject private var project = ProjectViewModel()
    @State private var showWelcomeScreen = !WelcomeScreenState.hasSeenWelcome
    @State private var showTestCasesPanel = false
    @State private var scrollToLine: Int? = nil
    @State private var violationToastText: String? = nil
    @State private var violationToastDismissTask: DispatchWorkItem? = nil
    @State private var showConsole = true
    @State private var consoleHeight: CGFloat = 200
    @State private var consoleHeightAtDragStart: CGFloat? = nil
    @State private var showExamSettings = false

    private let minConsoleHeight: CGFloat = 100
    private let maxConsoleHeight: CGFloat = 560

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            HSplitView {
                SidebarView(
                    project: project,
                    selectedURL: editor.currentFileURL,
                    onSelectFile: handleFileSelection,
                    disabled: exam.isActive
                )
                    .frame(minWidth: 200, idealWidth: 230, maxWidth: 340)

                VStack(spacing: 0) {
                    // Exam sessions stay single-file by design, so the tab
                    // bar (which implies "juggle several files") is hidden
                    // while a session is active.
                    if !exam.isActive {
                        TabBarView(editor: editor)
                        if !editor.openTabs.isEmpty {
                            Divider()
                        }
                    }
                    CodeEditorView(
                        text: $editor.sourceCode,
                        indentWidth: editor.indentWidth,
                        diagnostics: editor.diagnostics,
                        scrollToLine: $scrollToLine
                    ) { line, column in
                        editor.updateCursorPosition(line: line, column: column)
                    }
                }
                .frame(minWidth: 400)
            }

            if showConsole {
                resizeHandle
                bottomPanel
                    .frame(height: consoleHeight)
            }

            Divider()
            statusBar
        }
        .frame(minWidth: 900, minHeight: 560)
        .confirmationDialog(
            "Start Exam Mode?",
            isPresented: $exam.showStartConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Editor & Start", role: .destructive) {
                exam.confirmStart(editor: editor)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Exam Mode clears the current code so nothing written or pasted beforehand carries into the session. This can't be undone.")
        }
        .sheet(isPresented: $showWelcomeScreen, onDismiss: {
            WelcomeScreenState.hasSeenWelcome = true
        }) {
            WelcomeScreen()
        }
        .sheet(isPresented: $showTestCasesPanel) {
            TestCasesPanel(editor: editor)
        }
        .overlay(alignment: .top) {
            if let text = violationToastText {
                violationToast(text)
                    .padding(.top, 50)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: exam.violationLog.count) { oldCount, newCount in
            guard newCount > oldCount, let latest = exam.violationLog.last else { return }
            showViolationToast(latest)
        }
    }

    /// A brief, non-disruptive banner shown the instant a violation is
    /// logged — so a student sees exactly what just got flagged (e.g. an
    /// accidental Cmd+Space) right away, instead of only discovering it by
    /// scrolling the session log later. Transparency here is the point:
    /// nothing goes on the record silently.
    private func violationToast(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .appGlass(in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 6)
    }

    private func showViolationToast(_ text: String) {
        violationToastDismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            violationToastText = text
        }
        let task = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.25)) {
                violationToastText = nil
            }
        }
        violationToastDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: task)
    }

    // MARK: - Resize handle (manual terminal sizing)

    /// A thin draggable strip above the terminal/build-output panel. Drag it
    /// up or down to resize the panel by hand instead of being stuck with a
    /// fixed height range.
    private var resizeHandle: some View {
        ZStack {
            Divider()
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: XcodeTheme.gutterText))
                .frame(width: 36, height: 4)
                .opacity(0.6)
        }
        .frame(height: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let base = consoleHeightAtDragStart ?? consoleHeight
                    if consoleHeightAtDragStart == nil { consoleHeightAtDragStart = base }
                    let proposed = base - value.translation.height
                    consoleHeight = min(max(proposed, minConsoleHeight), maxConsoleHeight)
                }
                .onEnded { _ in
                    consoleHeightAtDragStart = nil
                }
        )
    }

    // MARK: - Bottom panel (build output + session log)

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Build Output")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                let errorCount = editor.diagnostics.filter { $0.severity == .error }.count
                let warningCount = editor.diagnostics.filter { $0.severity == .warning }.count
                if errorCount > 0 {
                    Label("\(errorCount)", systemImage: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                if warningCount > 0 {
                    Label("\(warningCount)", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }

                Spacer()

                Button {
                    showConsole = false
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.glass)
                .help("Hide build output")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .appGlass()

            if !editor.diagnostics.isEmpty {
                Divider()
                diagnosticsListView
            }

            Divider()

            // Left solid — a terminal-style panel benefits from a stable,
            // high-contrast background so error/warning colors stay readable;
            // only the surrounding chrome (this header, the toolbar, the
            // sidebar) gets the glass treatment.
            ScrollView {
                ConsoleOutputView(output: editor.output)
            }
            .background(Color(nsColor: XcodeTheme.consoleBackground))

            if exam.isActive || !exam.violationLog.isEmpty {
                Divider()
                sessionLogPanel
            }
        }
    }

    /// A compact, clickable list of the current compile's errors/warnings —
    /// tapping one jumps the editor's cursor straight to that line, instead
    /// of making the student hunt through raw compiler text for a line
    /// number. Capped at a scrollable strip so a file with many errors
    /// doesn't push the console text out of view.
    private var diagnosticsListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(editor.diagnostics) { diagnostic in
                    Button {
                        scrollToLine = diagnostic.line
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: diagnostic.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(diagnostic.severity == .error ? .red : .orange)
                                .font(.system(size: 10))
                            Text("Line \(diagnostic.line):")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(diagnostic.message)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Jump to line \(diagnostic.line)")
                }
            }
        }
        .frame(maxHeight: 90)
        .background(Color(nsColor: XcodeTheme.gutterBackground))
    }

    // MARK: - Toolbar (Xcode-style)

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundColor(.accentColor)
                Text(editor.displayFileName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if editor.isDirty {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .help("Unsaved changes")
                }
                Text(exam.isActive ? "EXAM MODE" : "Regular Mode")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(exam.isActive ? Color.red : Color.gray.opacity(0.25))
                    .foregroundColor(exam.isActive ? .white : .secondary)
                    .clipShape(Capsule())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .layoutPriority(1)

            Spacer()
            Picker("", selection: $editor.selectedLanguage) {
                ForEach(SupportedLanguage.allCases, id: \.self) { lang in
                    Text(lang.rawValue).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .disabled(exam.isActive)
            
            .onChange(of: editor.selectedLanguage) { oldValue, newValue in
                if editor.currentFileURL == nil {
                    editor.resetToTemplate()
                }
            }

            Stepper("Indent: \(editor.indentWidth)", value: $editor.indentWidth, in: 2...8, step: 2)
                .fixedSize()

            Divider().frame(height: 20)

            toolbarIconButton(systemImage: "folder.badge.plus", help: "Open Folder as Project") {
                project.openFolderPicker()
            }
            .disabled(exam.isActive)

            toolbarIconButton(systemImage: "square.and.arrow.down", help: "Open File") {
                editor.open()
            }
            .disabled(exam.isActive)

            toolbarIconButton(systemImage: "square.and.arrow.up", help: "Save") {
                editor.save()
            }

            if !exam.isActive {
                toolbarIconButton(systemImage: "checklist", help: "Test Cases & Complexity Notes") {
                    showTestCasesPanel = true
                }
            }

            toolbarIconButton(
                systemImage: showConsole ? "terminal.fill" : "terminal",
                help: showConsole ? "Hide Build Output" : "Show Build Output"
            ) {
                showConsole.toggle()
            }

            if exam.isActive {
                Label(exam.timeRemainingFormatted, systemImage: "timer")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(exam.timeRemaining < 60 ? .red : .primary)
                Label("\(exam.attemptsRemaining) runs left", systemImage: "play.slash")
                    .font(.system(size: 11))
                    .foregroundColor(exam.attemptsRemaining <= 2 ? .red : .secondary)
            } else {
                examSettingsButton
            }

            Button(action: handleExamModeButtonTap) {
                Label(exam.isActive ? "Exit Exam Mode" : "Start Exam Mode",
                      systemImage: exam.isActive ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.glassProminent)
            .tint(exam.isActive ? .red : .blue)

            Button(action: attemptCompile) {
                Label(editor.isCompiling ? "Building..." : "Run", systemImage: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.glassProminent)
            .tint(.green)
            .disabled(editor.isCompiling || !exam.canCompile)
            .keyboardShortcut(.return, modifiers: .command)

            toolbarIconButton(systemImage: "questionmark.circle", help: "Permissions & setup info") {
                showWelcomeScreen = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .appGlass()
    }

    /// Lets the student/instructor configure duration and attempt cap
    /// before starting a session — not adjustable once locked in. Supports
    /// exact manual values via steppers/text entry, plus quick presets.
    private var examSettingsButton: some View {
        Button {
            showExamSettings = true
        } label: {
            Label("\(exam.durationMinutes)m · \(exam.maxCompileAttempts) runs", systemImage: "gearshape")
                .font(.system(size: 11))
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .popover(isPresented: $showExamSettings, arrowEdge: .bottom) {
            examSettingsPopover
        }
    }

    private var examSettingsPopover: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Exam Setup")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Duration").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                HStack {
                    Stepper(value: $exam.durationMinutes, in: 1...480, step: 1) {
                        Text("")
                    }
                    .labelsHidden()
                    TextField("Minutes", value: $exam.durationMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("minutes")
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                        Button("\(minutes)m") { exam.durationMinutes = minutes }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Max Compile Attempts").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                HStack {
                    Stepper(value: $exam.maxCompileAttempts, in: 1...200, step: 1) {
                        Text("")
                    }
                    .labelsHidden()
                    TextField("Attempts", value: $exam.maxCompileAttempts, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("attempts")
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach([5, 10, 15, 20], id: \.self) { count in
                        Button("\(count)") { exam.maxCompileAttempts = count }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { showExamSettings = false }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 300)
    }

    private func toolbarIconButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.glass)
        .help(help)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            CursorPositionLabel(cursor: editor.cursorPosition)
            Label("\(editor.lineCount) lines", systemImage: "text.alignleft")
            Label(editor.selectedLanguage.rawValue, systemImage: "chevron.left.forwardslash.chevron.right")
            Label("Indent: \(editor.indentWidth) spaces", systemImage: "arrow.right.to.line")
            buildStatusLabel
            if exam.isActive, let savedLabel = exam.autosaveRelativeLabel {
                Label(savedLabel, systemImage: "checkmark.icloud")
                    .foregroundColor(.secondary)
            }
            Spacer()
            if exam.isActive {
                Label("Locked", systemImage: "lock.fill")
                    .foregroundColor(.red)
            } else {
                Label("Unlocked", systemImage: "lock.open")
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .appGlass()
    }

    @ViewBuilder
    private var buildStatusLabel: some View {
        switch editor.lastBuildStatus {
        case .none:
            EmptyView()
        case .success:
            Label(editor.lastBuildStatus.label, systemImage: editor.lastBuildStatus.systemImage)
                .foregroundColor(.green)
        case .failure:
            Label(editor.lastBuildStatus.label, systemImage: editor.lastBuildStatus.systemImage)
                .foregroundColor(.red)
        }
    }

    // MARK: - Session log

    private var sessionLogPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Session Log")
                .font(.caption).bold()
                .padding(.horizontal, 8).padding(.top, 6)
            ScrollView {
                ForEach(exam.violationLog.indices, id: \.self) { i in
                    Text(exam.violationLog[i])
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }
            }
            .frame(maxHeight: 120)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Actions

    private func handleExamModeButtonTap() {
        if exam.isActive {
            exam.stopAndExport(editor: editor)
        } else {
            exam.requestStart()
        }
    }

    private func attemptCompile() {
        guard exam.recordCompileAttempt() else { return }
        showConsole = true
        editor.compile()
    }

    /// Called when a file is tapped in the project sidebar. Opens it as a
    /// tab (or activates its existing tab) — unsaved edits in whatever's
    /// currently open are kept safe in that tab's own buffer, so there's
    /// nothing to discard by switching.
    private func handleFileSelection(_ url: URL) {
        editor.openFile(at: url)
    }
}

#Preview {
    ContentView()
}

/// Reads `CursorPositionModel` directly rather than through `EditorViewModel`
/// so that a cursor move — which happens on nearly every keystroke and every
/// arrow key press — only invalidates this one small label instead of
/// `ContentView`'s entire body (toolbar, sidebar, tab bar, editor).
private struct CursorPositionLabel: View {
    @ObservedObject var cursor: CursorPositionModel

    var body: some View {
        Label("Line \(cursor.line), Col \(cursor.column)", systemImage: "text.cursor")
    }
}

