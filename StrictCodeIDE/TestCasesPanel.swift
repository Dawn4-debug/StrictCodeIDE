import SwiftUI

/// A practice-mode panel: custom test cases with side-by-side actual vs
/// expected output, plus a simple complexity notes field. Intentionally
/// left out of Exam Mode — this is a practice tool, not an exam feature.
struct TestCasesPanel: View {
    @ObservedObject var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    complexitySection
                    Divider()
                    testCasesSection
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 720, height: 600)
        .background(Color(nsColor: XcodeTheme.editorBackground))
    }

    private var header: some View {
        HStack {
            Text("Practice Tools")
                .font(.title3).bold()
            Spacer()
            Button {
                editor.runTestCases()
            } label: {
                Label(editor.isRunningTests ? "Running..." : "Run All Tests", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(editor.isRunningTests || editor.testCases.isEmpty)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var complexitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Complexity Notes", systemImage: "function")
                .font(.headline)
            Text("Jot down your solution's time/space complexity — good habit to build before an interview or exam asks for it.")
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: $editor.complexityNotes)
                .font(.system(size: 13, design: .monospaced))
                .frame(height: 70)
                .padding(6)
                .background(Color(nsColor: XcodeTheme.consoleBackground).opacity(0.3))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.25)))
        }
    }

    private var testCasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Test Cases", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Button(action: editor.addTestCase) {
                    Label("Add Test Case", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if editor.testCases.isEmpty {
                Text("No test cases yet. Add one to test your code against a specific input and expected output.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
            }

            ForEach(editor.testCases) { testCase in
                testCaseRow(testCase)
            }
        }
    }

    private func testCaseRow(_ testCase: TestCase) -> some View {
        let result = editor.testResults.first { $0.testCase.id == testCase.id }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(testCase.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let result = result {
                    Label(result.passed ? "Pass" : "Fail", systemImage: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(result.passed ? .green : .red)
                }
                Button(role: .destructive) {
                    editor.removeTestCase(id: testCase.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            HStack(alignment: .top, spacing: 12) {
                labeledEditor(
                    title: "Input (stdin)",
                    text: Binding(
                        get: { testCase.input },
                        set: { editor.updateTestCase(id: testCase.id, input: $0) }
                    )
                )
                labeledEditor(
                    title: "Expected Output",
                    text: Binding(
                        get: { testCase.expectedOutput },
                        set: { editor.updateTestCase(id: testCase.id, expectedOutput: $0) }
                    )
                )
            }

            if let result = result {
                labeledStaticText(
                    title: "Actual Output",
                    text: result.actualOutput.isEmpty ? "(no output)" : result.actualOutput,
                    color: result.passed ? .green : .red
                )
            }
        }
        .padding(12)
        .background(Color(nsColor: XcodeTheme.toolbarBackground).opacity(0.5))
        .cornerRadius(8)
    }

    private func labeledEditor(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextEditor(text: text)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 60)
                .padding(4)
                .background(Color(nsColor: XcodeTheme.consoleBackground).opacity(0.3))
                .cornerRadius(6)
        }
        .frame(maxWidth: .infinity)
    }

    private func labeledStaticText(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(Color(nsColor: XcodeTheme.consoleBackground).opacity(0.3))
                .cornerRadius(6)
        }
    }
}
