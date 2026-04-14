import SwiftUI

struct NoteView: View {
    @ObservedObject var appState: AppState

    @State private var focusToken: Int = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NativeTextView(
                text: $appState.noteText,
                focusToken: $focusToken,
                isEditable: !appState.isExporting
            )

            if appState.isExporting {
                ExportingBadge()
                    .padding(10)
                    .transition(.opacity)
            }
        }
        .padding(12)
        .background(Color.clear)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: appState.isExporting)
        .onReceive(NotificationCenter.default.publisher(for: .notePopFocusEditor)) { _ in
            focusToken &+= 1
        }
    }
}

private struct ExportingBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Exporting…")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .allowsHitTesting(false)
    }
}

/// A minimal NSTextView wrapper so we can reliably focus the editor.
struct NativeTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var focusToken: Int
    var isEditable: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 2, height: 6)

        let scrollView = NSScrollView()
        // Keep the scroller layout stable; we'll fade/disable it when not needed.
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
            textView.isSelectable = true
        }

        if textView.string != text {
            textView.string = text
        }

        updateScrollbarVisibility(scrollView: nsView, textView: textView)

        // When focusToken changes, focus the text view.
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    private func updateScrollbarVisibility(scrollView: NSScrollView, textView: NSTextView) {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)

        // Account for text container insets.
        let contentHeight = usedRect.height + (textView.textContainerInset.height * 2)
        let visibleHeight = scrollView.contentView.bounds.height

        // Only show a scrollbar if scrolling is actually needed.
        let needsScroll = contentHeight > (visibleHeight + 1)

        // Avoid toggling hasVerticalScroller (can cause constraint churn during layout).
        // Instead, fade/disable the scroller when it isn't needed.
        if let scroller = scrollView.verticalScroller {
            scroller.isEnabled = needsScroll
            scroller.alphaValue = needsScroll ? 1.0 : 0.0
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var lastFocusToken: Int = 0

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}
