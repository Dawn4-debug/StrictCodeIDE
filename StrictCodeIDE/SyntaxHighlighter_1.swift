import AppKit

/// Minimal regex-based syntax highlighter using colors matched to Xcode's
/// default dark theme (see XcodeTheme.swift). Not a full parser — just
/// enough to make the editor feel native for C/C++/Java.
///
/// Performance note: matching is the expensive part (six regex passes over
/// the whole document), so it's split from applying. `computeRuns(for:)` is
/// pure — it only reads a `String` — so it's safe to run on a background
/// queue. `apply(_:to:)` just paints the precomputed ranges onto the text
/// storage, which is cheap and must stay on the main thread. `highlight(_:)`
/// does both synchronously, for the few call sites (initial load, tab
/// switch) where there's no previous frame to fall back on.
enum SyntaxHighlighter {

    struct Run {
        let color: NSColor
        let ranges: [NSRange]
    }

    private static let keywords = [
        "int", "float", "double", "char", "void", "long", "short", "unsigned",
        "signed", "struct", "typedef", "const", "static", "return", "if", "else",
        "for", "while", "do", "switch", "case", "break", "continue", "default",
        "class", "public", "private", "protected", "new", "this",
        "import", "package", "extends", "implements", "interface",
        "true", "false", "null"
    ]

    private static let types = ["String", "boolean", "Integer", "Double", "Object"]

    private static let keywordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
    private static let typePattern = "\\b(" + types.joined(separator: "|") + ")\\b"
    private static let stringPattern = "\"(?:\\\\.|[^\"\\\\])*\""
    private static let commentPattern = "(//.*$|/\\*[\\s\\S]*?\\*/)"
    private static let numberPattern = "\\b[0-9]+(\\.[0-9]+)?\\b"
    private static let preprocessorPattern = "^\\s*#\\w+"

    /// Each regex is compiled exactly once (Swift lazily initializes `static
    /// let`s on first access, thread-safely) instead of being rebuilt from
    /// its pattern string on every single keystroke, which is where most of
    /// the old per-keystroke cost came from.
    private static let keywordRegex = try! NSRegularExpression(pattern: keywordPattern)
    private static let typeRegex = try! NSRegularExpression(pattern: typePattern)
    private static let stringRegex = try! NSRegularExpression(pattern: stringPattern)
    private static let commentRegex = try! NSRegularExpression(pattern: commentPattern, options: [.anchorsMatchLines])
    private static let numberRegex = try! NSRegularExpression(pattern: numberPattern)
    private static let preprocessorRegex = try! NSRegularExpression(pattern: preprocessorPattern, options: [.anchorsMatchLines])

    private static let colorRegexPairs: [(NSColor, NSRegularExpression)] = [
        (XcodeTheme.keyword, keywordRegex),
        (XcodeTheme.type, typeRegex),
        (XcodeTheme.string, stringRegex),
        (XcodeTheme.comment, commentRegex),
        (XcodeTheme.number, numberRegex),
        (XcodeTheme.preprocessor, preprocessorRegex),
    ]

    /// Pure computation: matches every pattern against `text` and returns
    /// the resulting colored ranges. Does not touch AppKit, so it's safe to
    /// call from any thread — this is what makes async highlighting possible.
    static func computeRuns(for text: String) -> [Run] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return colorRegexPairs.map { color, regex in
            let matches = regex.matches(in: text, options: [], range: fullRange)
            return Run(color: color, ranges: matches.map { $0.range })
        }
    }

    /// Paints precomputed runs onto the text storage. Cheap — just attribute
    /// writes, no matching — so it's fine to call synchronously on the main
    /// thread even for a large document.
    static func apply(_ runs: [Run], to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let selectedRanges = textView.selectedRanges

        // 💡 Fix: Capture the editor's live font size to prevent the property reset loop
        let currentFont = textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        textStorage.beginEditing()
        textStorage.addAttribute(.foregroundColor, value: XcodeTheme.plainText, range: fullRange)
        textStorage.addAttribute(.font, value: currentFont, range: fullRange) // Use live font
        
        for run in runs {
            for range in run.ranges where range.location + range.length <= textStorage.length {
                textStorage.addAttribute(.foregroundColor, value: run.color, range: range)
            }
        }
        textStorage.endEditing()
        textView.selectedRanges = selectedRanges
    }

    /// Synchronous convenience for call sites with no prior frame to keep
    /// showing while work happens in the background (initial load, opening
    /// a different file). For live typing, prefer computing `computeRuns`
    /// off the main thread and calling `apply` with the result instead.
    static func highlight(_ textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        apply(computeRuns(for: textStorage.string), to: textView)
    }

    // MARK: - Inline compiler diagnostics (squiggly underlines)

    /// Raw values NSTextView's `.spellingState` attribute understands:
    /// 1 draws a red squiggle (normally "misspelling"), 2 draws a green one
    /// (normally "grammar"). AppKit doesn't expose a named enum for these,
    /// just documents the raw ints, so we repurpose them here for errors vs
    /// warnings instead of writing custom underline-drawing code.
    private enum SpellingState: Int {
        case spelling = 1
        case grammar = 2
    }

    /// Draws a red squiggle under lines with compile errors and an orange
    /// one under lines with warnings, using AppKit's built-in spell-check
    /// squiggle attribute rather than any custom drawing. Call after
    /// `highlight(_:)` any time `diagnostics` changes (new compile, or the
    /// text changed and old diagnostics no longer apply).
    static func applyDiagnostics(_ textView: NSTextView, diagnostics: [CompileDiagnostic]) {
        guard let textStorage = textView.textStorage else { return }
        let fullText = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: fullText.length)

        textStorage.beginEditing()
        textStorage.removeAttribute(.spellingState, range: fullRange)

        if !diagnostics.isEmpty {
            // Diagnostics are keyed by line number, so one pass over the
            // text builds a line->range lookup instead of re-walking the
            // whole document from the start for every individual diagnostic
            // (which is what happened before when there were several
            // errors/warnings in the same file).
            let lineStarts = lineRanges(in: fullText)
            for diagnostic in diagnostics {
                guard diagnostic.line >= 1, diagnostic.line <= lineStarts.count else { continue }
                var lineRange = lineStarts[diagnostic.line - 1]
                if lineRange.length > 0,
                   fullText.substring(with: NSRange(location: NSMaxRange(lineRange) - 1, length: 1)) == "\n" {
                    lineRange.length -= 1
                }
                guard lineRange.length > 0 else { continue }
                let state: SpellingState = diagnostic.severity == .error ? .spelling : .grammar
                textStorage.addAttribute(.spellingState, value: state.rawValue, range: lineRange)
            }
        }

        textStorage.endEditing()
    }

    /// One linear pass that returns the `NSRange` of every line in `text`,
    /// in order — replaces the old approach of re-scanning from the start
    /// of the document once per diagnostic.
    private static func lineRanges(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var index = 0
        while index < text.length {
            let range = text.lineRange(for: NSRange(location: index, length: 0))
            ranges.append(range)
            index = NSMaxRange(range)
        }
        // A trailing empty "line" after a final newline (or an entirely
        // empty document) still counts as a line a diagnostic can point at.
        if text.length == 0 || text.hasSuffix("\n") {
            ranges.append(NSRange(location: text.length, length: 0))
        }
        return ranges
    }
}
