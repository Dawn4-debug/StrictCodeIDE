import Foundation

/// Severity of a single compiler diagnostic. Only two buckets — everything
/// the compilers we support emit is either an error or a warning.
enum DiagnosticSeverity {
    case error
    case warning
}

/// One line/column-addressable problem reported by the compiler, parsed out
/// of the raw stdout/stderr blob so the UI can point at the exact broken
/// line instead of just dumping text into the console.
struct CompileDiagnostic: Identifiable, Equatable {
    let id = UUID()
    let line: Int
    let column: Int
    let severity: DiagnosticSeverity
    let message: String

    static func == (lhs: CompileDiagnostic, rhs: CompileDiagnostic) -> Bool {
        lhs.line == rhs.line && lhs.column == rhs.column && lhs.severity == rhs.severity && lhs.message == rhs.message
    }
}

/// Parses compiler output into `CompileDiagnostic`s.
///
/// clang/clang++ (C/C++) always emit `path:line:col: error|warning: message`.
/// javac (Java) emits `path:line: error|warning: message` — no column, and
/// the exact column is instead implied by a caret ("^") on the following
/// line, which we don't need since we only highlight whole lines.
enum DiagnosticParser {
    private static let clangPattern = #"^.*?:(\d+):(\d+):\s*(error|warning):\s*(.+)$"#
    private static let javacPattern = #"^.*?:(\d+):\s*(error|warning):\s*(.+)$"#

    static func parse(_ output: String) -> [CompileDiagnostic] {
        var results: [CompileDiagnostic] = []
        for rawLine in output.components(separatedBy: "\n") {
            if let diagnostic = matchClang(rawLine) {
                results.append(diagnostic)
            } else if let diagnostic = matchJavac(rawLine) {
                results.append(diagnostic)
            }
        }
        return results
    }

    private static func matchClang(_ line: String) -> CompileDiagnostic? {
        guard let regex = try? NSRegularExpression(pattern: clangPattern) else { return nil }
        let nsLine = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
              m.numberOfRanges == 5,
              let lineNumber = Int(nsLine.substring(with: m.range(at: 1))),
              let column = Int(nsLine.substring(with: m.range(at: 2)))
        else { return nil }
        let severity: DiagnosticSeverity = nsLine.substring(with: m.range(at: 3)) == "error" ? .error : .warning
        let message = nsLine.substring(with: m.range(at: 4))
        return CompileDiagnostic(line: lineNumber, column: column, severity: severity, message: message)
    }

    private static func matchJavac(_ line: String) -> CompileDiagnostic? {
        guard let regex = try? NSRegularExpression(pattern: javacPattern) else { return nil }
        let nsLine = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
              m.numberOfRanges == 4,
              let lineNumber = Int(nsLine.substring(with: m.range(at: 1)))
        else { return nil }
        let severity: DiagnosticSeverity = nsLine.substring(with: m.range(at: 2)) == "error" ? .error : .warning
        let message = nsLine.substring(with: m.range(at: 3))
        return CompileDiagnostic(line: lineNumber, column: 1, severity: severity, message: message)
    }
}
