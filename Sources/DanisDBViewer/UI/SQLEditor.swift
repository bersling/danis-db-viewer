import AppKit
import SwiftUI

/// SQL keywords for highlighting + completion.
enum SQLKeywords {
    static let all: [String] = """
        SELECT FROM WHERE INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE VIEW INDEX DROP ALTER ADD \
        PRIMARY KEY FOREIGN REFERENCES NOT NULL UNIQUE DEFAULT AUTO_INCREMENT AUTOINCREMENT \
        JOIN LEFT RIGHT INNER OUTER CROSS FULL ON AS AND OR IN IS LIKE BETWEEN EXISTS \
        GROUP BY ORDER HAVING LIMIT OFFSET DISTINCT UNION ALL EXCEPT INTERSECT \
        CASE WHEN THEN ELSE END CAST COALESCE NULLIF COUNT SUM AVG MIN MAX \
        BEGIN COMMIT ROLLBACK TRANSACTION PRAGMA EXPLAIN ANALYZE VACUUM WITH RECURSIVE \
        INTEGER TEXT REAL BLOB NUMERIC VARCHAR CHAR BOOLEAN DATE TIMESTAMP SERIAL BIGINT SMALLINT \
        TRUE FALSE ASC DESC IF RETURNING CONSTRAINT CASCADE RESTRICT TRUNCATE RENAME COLUMN TO SHOW
        """.split(separator: " ").map(String.init)

    static let set: Set<String> = Set(all)
}

/// Names offered by completion, refreshed from introspection.
struct SQLCompletionContext {
    var tableNames: [String] = []
    var columnNames: [String] = []
}

/// NSTextView-backed SQL editor: Darcula syntax highlighting, keyword/schema
/// completion (Ctrl+Space or as-you-type), Cmd+Enter handled by the host view.
struct SQLEditor: NSViewRepresentable {
    @Binding var text: String
    var completion: SQLCompletionContext
    var onExecute: () -> Void          // ⌘⏎
    var onCaretChange: (Int, NSRange) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = Theme.editorNSFont
        textView.backgroundColor = Theme.editorNSBackground
        textView.insertionPointColor = .white
        textView.textColor = Theme.sqlDefault
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.string = text
        scrollView.hasVerticalScroller = true
        context.coordinator.textView = textView
        context.coordinator.highlight()

        // Test hook: focus + trigger completion on a partial word for screenshots.
        if let partial = ProcessInfo.processInfo.environment["DANIS_COMPLETE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak textView] in
                guard let textView else { return }
                textView.window?.makeFirstResponder(textView)
                textView.string = partial
                self.text = partial
                textView.setSelectedRange(NSRange(location: (partial as NSString).length, length: 0))
                context.coordinator.highlight()
                textView.complete(nil)
            }
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.highlight()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLEditor
        weak var textView: NSTextView?

        init(_ parent: SQLEditor) {
            self.parent = parent
        }

        /// True when the last edit inserted a single identifier character — the
        /// cue to pop live completion (typing a letter, not deleting/pasting).
        private var lastEditWasWordChar = false

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            if let s = replacementString, s.count == 1, let c = s.first,
               c.isLetter || c.isNumber || c == "_" {
                lastEditWasWordChar = true
            } else {
                lastEditWasWordChar = false
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            highlight()
            if lastEditWasWordChar { scheduleAutocomplete(textView) }
        }

        /// Show the completion list as you type, but only when candidates exist
        /// (avoids the "No Completions" flash on non-matching input).
        private func scheduleAutocomplete(_ textView: NSTextView) {
            let range = textView.rangeForUserCompletion
            guard range.location != NSNotFound, range.length > 0 else { return }
            let partial = (textView.string as NSString).substring(with: range)
            guard partial.count >= 1, !candidates(forPartial: partial).isEmpty else { return }
            // Defer so the just-typed character is committed before the popup.
            DispatchQueue.main.async { [weak textView] in
                textView?.complete(nil)
            }
        }

        private func candidates(forPartial partial: String) -> [String] {
            let p = partial.lowercased()
            var out: [String] = []
            out += parent.completion.tableNames.filter { $0.lowercased().hasPrefix(p) }
            out += parent.completion.columnNames.filter { $0.lowercased().hasPrefix(p) }
            out += SQLKeywords.all.filter { $0.lowercased().hasPrefix(p) }
            var seen = Set<String>()
            return out.filter { seen.insert($0.lowercased()).inserted }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            parent.onCaretChange(textView.selectedRange().location, textView.selectedRange())
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // ⌘⏎ → execute
            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                parent.onExecute()
                return true
            }
            return false
        }

        // Candidate list for both live and manual (Esc/F5) completion.
        func textView(_ textView: NSTextView, completions words: [String],
                      forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            let partial = (textView.string as NSString).substring(with: charRange)
            guard !partial.isEmpty else { return [] }
            return candidates(forPartial: partial)
        }

        // MARK: Highlighting

        func highlight() {
            guard let textView, let storage = textView.textStorage else { return }
            let string = textView.string
            let full = NSRange(location: 0, length: (string as NSString).length)
            storage.beginEditing()
            storage.removeAttribute(.foregroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: Theme.sqlDefault, range: full)
            storage.addAttribute(.font, value: Theme.editorNSFont, range: full)

            apply(pattern: "\\b\\d+(\\.\\d+)?\\b", color: Theme.sqlNumber, in: string, storage: storage)
            for (i, word) in tokenRanges(in: string) {
                if SQLKeywords.set.contains(word.uppercased()) {
                    storage.addAttribute(.foregroundColor, value: Theme.sqlKeyword, range: i)
                }
            }
            apply(pattern: "'(?:[^']|'')*'", color: Theme.sqlString, in: string, storage: storage)
            apply(pattern: "--[^\\n]*", color: Theme.sqlComment, in: string, storage: storage)
            apply(pattern: "/\\*.*?\\*/", color: Theme.sqlComment, in: string, storage: storage, options: [.dotMatchesLineSeparators])
            storage.endEditing()
        }

        private func apply(pattern: String, color: NSColor, in string: String,
                           storage: NSTextStorage, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let full = NSRange(location: 0, length: (string as NSString).length)
            regex.enumerateMatches(in: string, range: full) { match, _, _ in
                if let range = match?.range {
                    storage.addAttribute(.foregroundColor, value: color, range: range)
                }
            }
        }

        private func tokenRanges(in string: String) -> [(NSRange, String)] {
            guard let regex = try? NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]*") else { return [] }
            let ns = string as NSString
            let full = NSRange(location: 0, length: ns.length)
            var result: [(NSRange, String)] = []
            regex.enumerateMatches(in: string, range: full) { match, _, _ in
                if let range = match?.range {
                    result.append((range, ns.substring(with: range)))
                }
            }
            return result
        }
    }
}
