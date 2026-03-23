import AppKit

/// Thin coordinator for the native NSTextView find bar.
/// Most functionality is free from `textView.usesFindBar = true`.
/// This class exists as an extension seam for future enhancements
/// (e.g., pre-filling the search field from a selection).
final class FindBarCoordinator {

    weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
    }

    /// Show the find bar and optionally pre-fill with the current selection.
    func activateFindBar() {
        guard let tv = textView else { return }

        // Pre-fill search field with current selection if it's a single line
        if let range = Range(tv.selectedRange(), in: tv.string) {
            let selected = String(tv.string[range])
            if !selected.isEmpty && !selected.contains("\n") {
                NSPasteboard(name: .find).clearContents()
                NSPasteboard(name: .find).setString(selected, forType: .string)
            }
        }

        tv.performFindPanelAction(nil)
    }
}
