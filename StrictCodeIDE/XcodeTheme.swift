import AppKit
import SwiftUI

/// Colors matched to Xcode's own default themes — both the dark theme and
/// the light one. Every color here is a *dynamic* NSColor: it resolves
/// differently depending on the system's current Light/Dark Mode setting,
/// so the whole app follows system appearance automatically, the same way
/// Xcode itself does. Nothing forces a fixed appearance anywhere else in
/// the app — this is the only place colors are defined.
enum XcodeTheme {

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static let editorBackground = dynamic(
        light: NSColor(calibratedWhite: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.114, green: 0.122, blue: 0.145, alpha: 1)
    )

    static let toolbarBackground = dynamic(
        light: NSColor(calibratedRed: 0.925, green: 0.925, blue: 0.937, alpha: 1),
        dark: NSColor(calibratedRed: 0.157, green: 0.165, blue: 0.192, alpha: 1)
    )

    static let gutterBackground = dynamic(
        light: NSColor(calibratedRed: 0.953, green: 0.953, blue: 0.961, alpha: 1),
        dark: NSColor(calibratedRed: 0.129, green: 0.137, blue: 0.161, alpha: 1)
    )

    static let gutterText = dynamic(
        light: NSColor(calibratedWhite: 0.55, alpha: 1),
        dark: NSColor(calibratedWhite: 0.45, alpha: 1)
    )

    static let plainText = dynamic(
        light: NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1),
        dark: NSColor(calibratedWhite: 0.92, alpha: 1)
    )

    /// The blinking text-insertion caret — dark in light mode, light in dark mode.
    static let insertionPoint = NSColor.textColor

    // Syntax colors — Xcode's default light and dark theme values.
    static let keyword = dynamic(
        light: NSColor(calibratedRed: 0.608, green: 0.137, blue: 0.576, alpha: 1),  // purple
        dark: NSColor(calibratedRed: 0.988, green: 0.373, blue: 0.639, alpha: 1)    // pink
    )
    static let string = dynamic(
        light: NSColor(calibratedRed: 0.769, green: 0.102, blue: 0.086, alpha: 1),  // red
        dark: NSColor(calibratedRed: 0.988, green: 0.416, blue: 0.365, alpha: 1)    // red-orange
    )
    static let comment = dynamic(
        light: NSColor(calibratedRed: 0.0, green: 0.455, blue: 0.165, alpha: 1),    // green
        dark: NSColor(calibratedRed: 0.424, green: 0.475, blue: 0.525, alpha: 1)    // grey-green
    )
    static let number = dynamic(
        light: NSColor(calibratedRed: 0.110, green: 0.0, blue: 0.812, alpha: 1),    // blue
        dark: NSColor(calibratedRed: 0.816, green: 0.749, blue: 0.412, alpha: 1)    // tan
    )
    static let preprocessor = dynamic(
        light: NSColor(calibratedRed: 0.490, green: 0.220, blue: 0.137, alpha: 1),  // brown
        dark: NSColor(calibratedRed: 0.988, green: 0.635, blue: 0.365, alpha: 1)    // orange
    )
    static let type = dynamic(
        light: NSColor(calibratedRed: 0.247, green: 0.431, blue: 0.459, alpha: 1),  // teal
        dark: NSColor(calibratedRed: 0.365, green: 0.816, blue: 0.847, alpha: 1)    // cyan
    )

    // Compile output console — terminal-style in both modes, but readable in each.
    static let consoleBackground = dynamic(
        light: NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.965, alpha: 1),
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.9)
    )
    static let consoleText = dynamic(
        light: NSColor(calibratedRed: 0.0, green: 0.42, blue: 0.14, alpha: 1),
        dark: NSColor(calibratedRed: 0.30, green: 1.0, blue: 0.42, alpha: 1)
    )

    // Selected-row / active-tab highlight — a neutral gray, matching Xcode's
    // own muted selection color, instead of the system accent blue (which
    // reads as an out-of-place bright highlight against this palette).
    static let selection = dynamic(
        light: NSColor(calibratedWhite: 0.82, alpha: 1),
        dark: NSColor(calibratedWhite: 0.30, alpha: 1)
    )

    static var selectionColor: Color { Color(nsColor: selection) }

    // MARK: - Liquid Glass

    /// Tint mixed into every glass surface in the app (toolbar, sidebar, tab
    /// bar, status bar). A soft neutral blue-gray, low-opacity in both
    /// appearances, so the glass reads as tinted rather than colored, and
    /// text/icons drawn on top stay legible regardless of what's behind it.
    private static let glassTintColor = dynamic(
        light: NSColor(calibratedRed: 0.55, green: 0.58, blue: 0.66, alpha: 0.16),
        dark: NSColor(calibratedRed: 0.30, green: 0.34, blue: 0.44, alpha: 0.24)
    )

    static var glassTint: Color { Color(nsColor: glassTintColor) }
}

extension View {
    /// Applies the app's standard "balanced" Liquid Glass chrome treatment —
    /// used for every toolbar, bar, and panel header so the whole app reads
    /// as one consistent glass surface rather than a patchwork of one-off
    /// tints. Centralized here so the strength/tint can be tuned in one place.
    @ViewBuilder
    func appGlass<S: Shape>(in shape: S = Rectangle()) -> some View {
        self.glassEffect(.regular.tint(XcodeTheme.glassTint), in: shape)
    }
}
