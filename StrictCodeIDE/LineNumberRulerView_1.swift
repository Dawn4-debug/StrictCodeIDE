import AppKit

/// Draws line numbers in a gutter to the left of the text view, the same
/// way Xcode's editor does. Attached as the `verticalRulerView` of the
/// enclosing NSScrollView.
final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    
    var currentFontSize: CGFloat {
            let savedSize = UserDefaults.standard.double(forKey: "appearance_fontSize")
            return savedSize == 0 ? 14 : CGFloat(savedSize) // Fallback defaults to 14pt
        }
    /// Compile errors/warnings for the current source, keyed by line so
    /// `drawLineNumbers` can badge the exact broken line instead of the
    /// student having to guess from the console text alone.
    var diagnostics: [CompileDiagnostic] = [] {
        didSet { needsDisplay = true }
    }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
       
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: UserDefaults.didChangeNotification, object: nil)
        }

        // 🌟 ADD THIS HELPER METHOD INSIDE THE CLASS TO FORCE A REDRAW 🌟
        @objc private func preferencesChanged() {
            DispatchQueue.main.async {
                self.needsDisplay = true
            }
        
        
        
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    /// The correct override point for custom ruler drawing (drawHairline()
    /// isn't a real overridable method — draw(_:) is what NSRulerView
    /// actually calls).
    override func draw(_ dirtyRect: NSRect) {
        XcodeTheme.gutterBackground.setFill()
        bounds.fill()

        let dividerRect = NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)
        NSColor.black.withAlphaComponent(0.3).setFill()
        dividerRect.fill()

        drawLineNumbers(in: dirtyRect)
    }

    private func drawLineNumbers(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let fullString = textView.string as NSString
        var lineNumber = fullString.substring(to: characterRange.location).components(separatedBy: "\n").count

        var index = characterRange.location
        let textContainerInset = textView.textContainerInset

        while index < NSMaxRange(characterRange) {
            let lineRange = fullString.lineRange(for: NSRange(location: index, length: 0))
            let glyphRangeForLine = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRangeForLine, in: textContainer)
            lineRect.origin.y += textContainerInset.height

            let diagnostic = diagnostics.first { $0.line == lineNumber }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: diagnostic == nil ? .regular : .bold),
                .foregroundColor: color(for: diagnostic)
            ]

            let numberString = "\(lineNumber)" as NSString
            let size = numberString.size(withAttributes: attributes)
            let yOffset = lineRect.origin.y - visibleRect.origin.y + (lineRect.height - size.height) / 2
            let drawRect = NSRect(x: ruleThickness - size.width - 8, y: yOffset, width: size.width, height: size.height)
            numberString.draw(in: drawRect, withAttributes: attributes)

            if let diagnostic {
                drawBadge(for: diagnostic, lineRect: lineRect, visibleOriginY: visibleRect.origin.y)
            }

            lineNumber += 1
            index = NSMaxRange(lineRange)
        }
    }

    private func color(for diagnostic: CompileDiagnostic?) -> NSColor {
        switch diagnostic?.severity {
        case .error: return .systemRed
        case .warning: return .systemOrange
        case nil: return XcodeTheme.gutterText
        }
    }

    /// A small filled circle at the left edge of the gutter — a compact
    /// stand-in for Xcode's warning/error badge icons, drawn directly
    /// rather than loading an image asset.
    private func drawBadge(for diagnostic: CompileDiagnostic, lineRect: NSRect, visibleOriginY: CGFloat) {
        let diameter: CGFloat = 6
        let yOffset = lineRect.origin.y - visibleOriginY + (lineRect.height - diameter) / 2
        let badgeRect = NSRect(x: 3, y: yOffset, width: diameter, height: diameter)
        let path = NSBezierPath(ovalIn: badgeRect)
        color(for: diagnostic).setFill()
        path.fill()
    }
}
