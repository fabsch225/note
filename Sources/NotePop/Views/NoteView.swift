import SwiftUI

struct NoteView: View {
    @ObservedObject var appState: AppState

    @State private var focusToken: Int = 0

    var body: some View {
        NativeTextView(text: $appState.noteText, focusToken: $focusToken)
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .onReceive(NotificationCenter.default.publisher(for: .notePopFocusEditor)) { _ in
                focusToken &+= 1
            }
    }
}

/// A minimal NSTextView wrapper so we can reliably focus the editor.
struct NativeTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var focusToken: Int

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 2, height: 6)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        // When focusToken changes, focus the text view.
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
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
