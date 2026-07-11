import SwiftUI

/// Horizontal tab bar above the editor, one tab per open file. Hidden
/// entirely during Exam Mode (handled by the caller) since locked sessions
/// stay single-file by design.
struct TabBarView: View {
    @ObservedObject var editor: EditorViewModel

    var body: some View {
        if !editor.openTabs.isEmpty {
            GlassEffectContainer(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(editor.openTabs, id: \.self) { url in
                            tab(for: url)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: 32)
                .appGlass()
            }
        }
    }

    @ViewBuilder
    private func tab(for url: URL) -> some View {
        let isActive = editor.currentFileURL == url

        HStack(spacing: 6) {
            Text(url.lastPathComponent)
                .font(.system(size: 12))
                .lineLimit(1)
            Button(action: { editor.closeTab(url: url) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        // Active tab gets its own glass "pill" that visually separates it
        // from the shared glass bar behind it — the same layered look
        // Liquid Glass uses for a selected segment inside a toolbar.
        .glassEffect(
            isActive ? .regular.tint(.accentColor.opacity(0.35)).interactive() : .clear,
            in: Capsule()
        )
        .contentShape(Capsule())
        .onTapGesture {
            guard !isActive else { return }
            editor.loadFile(url: url)
        }
    }
}
