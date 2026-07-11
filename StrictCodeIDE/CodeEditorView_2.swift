import SwiftUI
import AppKit

struct CodeEditorView: NSViewRepresentable {
    
    @Binding var text: String
    var indentWidth: Int
    var diagnostics: [CompileDiagnostic] = []
    @Binding var scrollToLine: Int?
    var onCursorChange: ((Int, Int) -> Void)? = nil
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        
        let showLines = UserDefaults.standard.object(forKey: "appearance_showLineNumbers") as? Bool ?? true
        scrollView.hasVerticalRuler = showLines
        scrollView.rulersVisible = showLines
        
        let contentSize = scrollView.contentSize
        let textView = StrictTextView(frame: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height))
        
        textView.textContainerInset = NSSize(width: 16, height: 12)
        
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        
        textView.backgroundColor = XcodeTheme.editorBackground
        textView.textColor = XcodeTheme.plainText
        textView.insertionPointColor = XcodeTheme.plainText
        scrollView.backgroundColor = XcodeTheme.editorBackground
        
        scrollView.documentView = textView
        
        let lineNumberRuler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = lineNumberRuler
        
        scrollView.tile()
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onCursorChange = onCursorChange
        guard let textView = nsView.documentView as? StrictTextView else { return }
        textView.indentWidth = indentWidth
        
        if textView.appearance != NSApp.appearance {
            textView.appearance = NSApp.appearance
            nsView.appearance = NSApp.appearance
        }
        
        if textView.backgroundColor != XcodeTheme.editorBackground {
            textView.backgroundColor = XcodeTheme.editorBackground
            nsView.backgroundColor = XcodeTheme.editorBackground
        }
        
        let savedFontSize = UserDefaults.standard.double(forKey: "appearance_fontSize")
        let targetSize = savedFontSize == 0 ? 13.0 : savedFontSize
        let editorFont = NSFont.monospacedSystemFont(ofSize: CGFloat(targetSize), weight: .regular)
        
        if textView.font?.pointSize != CGFloat(targetSize) {
            textView.font = editorFont
        }
        
        let tabWidth = UserDefaults.standard.integer(forKey: "editor_tabWidth") == 0 ? 4 : UserDefaults.standard.integer(forKey: "editor_tabWidth")
        let paragraphStyle = NSMutableParagraphStyle()
        let charWidth = textView.font?.advancement(forGlyph: 0).width ?? 7.0
        paragraphStyle.tabStops = []
        paragraphStyle.defaultTabInterval = CGFloat(tabWidth) * charWidth
        textView.defaultParagraphStyle = paragraphStyle
        
        textView.insertionPointColor = XcodeTheme.plainText
        textView.typingAttributes = [
            NSAttributedString.Key.font: editorFont,
            NSAttributedString.Key.foregroundColor: XcodeTheme.plainText,
            NSAttributedString.Key.paragraphStyle: paragraphStyle
        ]
        
        let showLines = UserDefaults.standard.object(forKey: "appearance_showLineNumbers") as? Bool ?? true
        if nsView.verticalRulerView == nil || !(nsView.verticalRulerView is LineNumberRulerView) {
            let lineNumberRuler = LineNumberRulerView(textView: textView)
            nsView.verticalRulerView = lineNumberRuler
        }
        if nsView.hasVerticalRuler != showLines {
            nsView.hasVerticalRuler = showLines
            nsView.rulersVisible = showLines
        }
        
        let enableWordWrap = UserDefaults.standard.bool(forKey: "editor_wordWrap")
        if let textContainer = textView.textContainer, textContainer.widthTracksTextView != enableWordWrap {
            if enableWordWrap {
                textContainer.widthTracksTextView = true
                textContainer.containerSize = NSSize(width: nsView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
                textView.isHorizontallyResizable = false
            } else {
                textContainer.widthTracksTextView = false
                textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                textView.isHorizontallyResizable = true
            }
        }
        
        if textView.string != text {
            let savedSelectedRanges = textView.selectedRanges
            textView.string = text
            
            // 💡 Fix: Only highlight here when a brand new file is loaded from disk.
            // This prevents state redraw loops from choking the main thread.
            SyntaxHighlighter.highlight(textView)
            
            nsView.verticalRulerView?.needsDisplay = true
            textView.selectedRanges = savedSelectedRanges
        }
        
        // Compiler diagnostics squiggles — reapplied whenever this view
        // updates so a fresh compile's results always show up, and so old
        // squiggles get cleared out once the diagnostics array is emptied
        // (e.g. right when a new compile starts).
        SyntaxHighlighter.applyDiagnostics(textView, diagnostics: diagnostics)
        
        if let targetLine = scrollToLine {
            jumpTo(line: targetLine, in: textView)
            // Reset async so we don't mutate SwiftUI state mid-update-cycle,
            // and so jumping to the same line twice in a row still works.
            DispatchQueue.main.async {
                scrollToLine = nil
            }
        }
        
        nsView.tile()
    }
    
    /// Moves the caret to the start of `line` (1-indexed, matching how
    /// compilers report line numbers) and scrolls it into view — used when
    /// tapping a diagnostic in the build output panel.
    private func jumpTo(line: Int, in textView: NSTextView) {
        let nsString = textView.string as NSString
        var lineStart = 0
        var currentLine = 1
        while lineStart <= nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: min(lineStart, nsString.length), length: 0))
            if currentLine == line {
                textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
                textView.scrollRangeToVisible(lineRange)
                textView.window?.makeFirstResponder(textView)
                return
            }
            if lineRange.length == 0 { break }
            lineStart = NSMaxRange(lineRange)
            currentLine += 1
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        var onCursorChange: ((Int, Int) -> Void)? = nil
        
        private var isApplyingEdit = false
        
        init(_ parent: CodeEditorView) {
            self.parent = parent
        }
        
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !isApplyingEdit else { return true }
            guard let replacement = replacementString else { return true }
            
            let autoIndent = UserDefaults.standard.object(forKey: "editor_autoIndentation") as? Bool ?? true
            let closeBrackets = UserDefaults.standard.bool(forKey: "editor_autoCloseBrackets")
            let closeQuotes = UserDefaults.standard.bool(forKey: "editor_autoCloseQuotes")
            let useSpaces = UserDefaults.standard.bool(forKey: "editor_useSpaces")
            let tabWidth = UserDefaults.standard.integer(forKey: "editor_tabWidth") == 0 ? 4 : UserDefaults.standard.integer(forKey: "editor_tabWidth")
            
            let selectedRange = textView.selectedRange()
            
            if replacement == "\t" && useSpaces {
                let spaceString = String(repeating: " ", count: tabWidth)
                isApplyingEdit = true
                textView.insertText(spaceString, replacementRange: affectedCharRange)
                isApplyingEdit = false
                return false
            }
            
            if replacement == "\n" && autoIndent {
                let nsString = textView.string as NSString
                let lineRange = nsString.lineRange(for: NSRange(location: affectedCharRange.location, length: 0))
                let startOfLine = lineRange.location
                let lengthUpToCursor = affectedCharRange.location - startOfLine
                let lineUpToCursor = nsString.substring(with: NSRange(location: startOfLine, length: lengthUpToCursor))
                
                var leadingWhitespace = ""
                for char in lineUpToCursor {
                    if char == " " || char == "\t" {
                        leadingWhitespace.append(char)
                    } else {
                        break
                    }
                }
                
                if lineUpToCursor.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("{") {
                    let indentBlock = useSpaces ? String(repeating: " ", count: tabWidth) : "\t"
                    leadingWhitespace += indentBlock
                }
                isApplyingEdit = true
                textView.insertText("\n\(leadingWhitespace)", replacementRange: affectedCharRange)
                isApplyingEdit = false
                return false
            }
            
            var pairMatch: String? = nil
            if closeBrackets {
                if replacement == "{" { pairMatch = "}" }
                else if replacement == "[" { pairMatch = "]" }
                else if replacement == "(" { pairMatch = ")" }
            }
            if closeQuotes {
                if replacement == "\"" { pairMatch = "\"" }
                else if replacement == "'" { pairMatch = "'" }
            }
            
            if let closingCharacter = pairMatch {
                isApplyingEdit = true
                textView.insertText("\(replacement)\(closingCharacter)", replacementRange: affectedCharRange)
                isApplyingEdit = false
                textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: 0))
                return false
            }
            
            return true
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            SyntaxHighlighter.highlight(textView)
            if self.parent.text != textView.string {
                self.parent.text = textView.string
            }
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selectedRange = textView.selectedRange()
            let nsString = textView.string as NSString
            
            var lineStart = 0
            var lineNumber = 0
            
            while lineStart < nsString.length {
                let lineRange = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
                if NSLocationInRange(selectedRange.location, lineRange) {
                    let column = selectedRange.location - lineRange.location + 1
                    onCursorChange?(lineNumber + 1, column)
                    return
                }
                lineStart = lineRange.location + lineRange.length
                lineNumber += 1
            }
        }
    }
    
    
    // MARK: - Native AppKit Safe Code Processing Canvas
    
    class StrictTextView: NSTextView {
        var indentWidth: Int = 4
        
        override func paste(_ sender: Any?) {
            // Enforces exam integrity protocols by intercepting clipboard stream hooks
            NSSound.beep()
            print("🚫 Paste blocked")
        }
        
        /// Drag-and-drop text insertion is a paste bypass otherwise — dragging
        /// selected text from another app onto the editor doesn't go through
        /// `paste(_:)` at all, so it has to be blocked separately here.
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            NSSound.beep()
            print("🚫 Drag-and-drop paste blocked")
            return false
        }
    }
}
