import SwiftUI

/// Renders compile/run output with per-line coloring — red for compiler
/// error lines, yellow for warnings, the normal console color otherwise.
/// Cheap to build: we already capture full stdout/stderr, this just colors
/// what's already there instead of adding new data collection.
struct ConsoleOutputView: View {
    let output: String

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(color(for: line))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .textSelection(.enabled)
    }

    private var lines: [String] {
        output.components(separatedBy: "\n")
    }

    private func color(for line: String) -> Color {
        let lowercased = line.lowercased()
        
        if lowercased.contains("error:") || line.hasPrefix("❌") {
            return .red
        }
        if lowercased.contains("warning:") {
            return .yellow
        }
        if line.hasPrefix("✅") {
            return .green
        }
        // 🌟 ACCENTUATES YOUR NEW BUILD TIME METRIC LINE 🌟
        if line.hasPrefix("⏱️") || lowercased.contains("build time:") {
            return .cyan
        }
        
        return Color(nsColor: XcodeTheme.consoleText)
    }
}
