import SwiftUI
import AppKit

/// Shown automatically on first launch, and reachable anytime afterward via
/// the toolbar's help button. Explains two things students/instructors
/// otherwise hit as confusing surprises: why Accessibility permission is
/// needed and where to grant it, and why macOS shows an "unidentified
/// developer" warning on first open.
struct WelcomeScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    section(
                        icon: "hand.raised.fill",
                        title: "Why this app asks for Accessibility permission",
                        color: .orange
                    ) {
                        Text("Exam Mode needs to detect when you switch to another app and block system shortcuts like Cmd+Tab while a locked session is active. macOS only allows this for apps you've explicitly trusted — that's what Accessibility permission grants.")
                        Text("This permission is **only used while Exam Mode is active**. In regular practice mode, nothing is monitored or blocked beyond paste.")
                            .foregroundColor(.secondary)
                    }

                    section(
                        icon: "gearshape.fill",
                        title: "Where to grant it",
                        color: .blue
                    ) {
                        Text("System Settings → Privacy & Security → Accessibility → enable Strict Code IDE.")
                        Text("You'll be prompted automatically the first time you click **Start Exam Mode**. If you miss it or say no, use the button below to jump straight there.")
                            .foregroundColor(.secondary)
                        Button(action: openAccessibilitySettings) {
                            Label("Open Accessibility Settings", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.bordered)
                    }

                    section(
                        icon: "exclamationmark.triangle.fill",
                        title: "Why macOS says this app is from an \"unidentified developer\"",
                        color: .yellow
                    ) {
                        Text("This isn't a sign anything is wrong with the app. Apple requires a paid Developer Program membership ($99/year) to \"notarize\" apps — a scan-and-sign process. This app hasn't gone through that yet, so Gatekeeper shows a caution screen on first launch.")
                        Text("To open it anyway: right-click the app → **Open** → confirm in the dialog. You'll only need to do this once.")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(28)
            }

            footer
        }
        .frame(width: 560, height: 560)
        .background(Color(nsColor: XcodeTheme.editorBackground))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Welcome to Strict Code IDE")
                    .font(.title2).bold()
            }
            Text("A couple of things worth knowing before you start.")
                .foregroundColor(.secondary)
        }
        .padding(24)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Got it") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    @ViewBuilder
    private func section<Content: View>(
        icon: String,
        title: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(color)
                Text(title).font(.headline)
            }
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .font(.system(size: 13))
            .padding(.leading, 26)
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Tracks whether the welcome screen has been shown before, so it only
/// appears automatically once — but stays reachable manually anytime.
enum WelcomeScreenState {
    private static let key = "hasSeenWelcomeScreen"

    static var hasSeenWelcome: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

#Preview {
    WelcomeScreen()
}
