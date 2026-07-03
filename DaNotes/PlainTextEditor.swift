//
//  PlainTextEditor.swift
//  DaNotes
//
//  A plain-text editor that disables smart substitutions (smart dashes,
//  smart quotes, text replacement) so Markdown source is kept verbatim.
//  SwiftUI's `TextEditor` offers no way to turn these off, so we wrap the
//  platform text view directly.
//

import SwiftUI

#if os(macOS)
import AppKit

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 20
    var controller: PlainTextEditorController? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        controller?.textView = textView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: fontSize)
        textView.drawsBackground = false

        // Disable the smart substitutions.
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        textView.string = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if textView.font?.pointSize != fontSize {
            textView.font = .systemFont(ofSize: fontSize)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        init(_ parent: PlainTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// Holds a reference to the live text view so callers can insert text at the
/// current caret / selection instead of appending to the end.
final class PlainTextEditorController {
    fileprivate weak var textView: NSTextView?

    /// Inserts `block` at the caret as its own paragraph, adding surrounding
    /// blank lines only where needed. Returns `false` when no text view is
    /// attached (e.g. the editor pane is hidden), so callers can fall back.
    @discardableResult
    func insertBlock(_ block: String) -> Bool {
        guard let textView else { return false }
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        let start = min(max(selection.location, 0), ns.length)
        let end = min(start + selection.length, ns.length)
        let padded = Self.paddedBlock(block, in: ns, start: start, end: end)
        let range = NSRange(location: start, length: end - start)

        if textView.shouldChangeText(in: range, replacementString: padded) {
            textView.textStorage?.replaceCharacters(in: range, with: padded)
            textView.didChangeText()
        }
        let caret = start + (padded as NSString).length
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        return true
    }

    fileprivate static func paddedBlock(_ block: String, in text: NSString, start: Int, end: Int) -> String {
        var prefix = ""
        var suffix = ""
        if start > 0 {
            let prev = text.substring(with: NSRange(location: start - 1, length: 1))
            if prev != "\n" {
                prefix = "\n\n"
            } else if start > 1, text.substring(with: NSRange(location: start - 2, length: 1)) != "\n" {
                prefix = "\n"
            }
        }
        if end < text.length {
            let next = text.substring(with: NSRange(location: end, length: 1))
            if next != "\n" {
                suffix = "\n\n"
            } else if end + 1 < text.length, text.substring(with: NSRange(location: end + 1, length: 1)) != "\n" {
                suffix = "\n"
            }
        }
        return prefix + block + suffix
    }
}
#endif

#if os(iOS)
import UIKit

struct PlainTextEditor: UIViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 20
    var controller: PlainTextEditorController? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        controller?.textView = textView
        textView.delegate = context.coordinator
        // Scale the body font with Dynamic Type, using `fontSize` as the base.
        textView.font = Self.scaledFont(fontSize)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear

        // Disable the smart substitutions.
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no

        // Markdown snippet controls integrated into the keyboard's own shortcuts
        // bar (like GoodNotes). DaNotes is iPad-only, so the shortcuts bar is
        // always available.
        if let controller {
            let assistant = textView.inputAssistantItem
            assistant.leadingBarButtonGroups = Self.assistantGroups(for: controller)
            assistant.trailingBarButtonGroups = []
        }

        textView.text = text
        return textView
    }

    /// Builds the grouped bar-button items shown in the iPad keyboard shortcuts
    /// bar. Each group collapses into a single menu button when the bar is too
    /// narrow to show every item.
    private static func assistantGroups(for controller: PlainTextEditorController) -> [UIBarButtonItemGroup] {
        struct Snippet { let symbol: String; let title: String; let run: () -> Void }

        func barItem(_ snippet: Snippet) -> UIBarButtonItem {
            UIBarButtonItem(primaryAction: UIAction(
                title: snippet.title,
                image: UIImage(systemName: snippet.symbol)
            ) { _ in snippet.run() })
        }

        func group(representative symbol: String, _ snippets: [Snippet]) -> UIBarButtonItemGroup {
            let menu = UIMenu(children: snippets.map { snippet in
                UIAction(title: snippet.title, image: UIImage(systemName: snippet.symbol)) { _ in snippet.run() }
            })
            let representative = UIBarButtonItem(image: UIImage(systemName: symbol), menu: menu)
            return UIBarButtonItemGroup(barButtonItems: snippets.map(barItem), representativeItem: representative)
        }

        let inline: [Snippet] = [
            Snippet(symbol: "bold", title: String(localized: .mdBold)) {
                controller.wrapInline(prefix: "**", suffix: "**", placeholder: String(localized: .mdBold))
            },
            Snippet(symbol: "italic", title: String(localized: .mdItalic)) {
                controller.wrapInline(prefix: "*", suffix: "*", placeholder: String(localized: .mdItalic))
            },
            Snippet(symbol: "strikethrough", title: String(localized: .mdStrikethrough)) {
                controller.wrapInline(prefix: "~~", suffix: "~~", placeholder: String(localized: .mdStrikethrough))
            },
            Snippet(symbol: "chevron.left.forwardslash.chevron.right", title: String(localized: .mdInlineCode)) {
                controller.wrapInline(prefix: "`", suffix: "`", placeholder: "code")
            },
            Snippet(symbol: "function", title: String(localized: .mdMath)) {
                controller.wrapInline(prefix: "$", suffix: "$", placeholder: "x")
            },
        ]
        let lines: [Snippet] = [
            Snippet(symbol: "number", title: String(localized: .mdHeading)) { controller.cycleHeading() },
            Snippet(symbol: "list.bullet", title: String(localized: .mdBulletList)) { controller.toggleLinePrefix("- ") },
            Snippet(symbol: "list.number", title: String(localized: .mdNumberedList)) { controller.toggleNumberedList() },
            Snippet(symbol: "text.quote", title: String(localized: .mdQuote)) { controller.toggleLinePrefix("> ") },
        ]
        let blocks: [Snippet] = [
            Snippet(symbol: "link", title: String(localized: .mdLink)) { controller.insertLink() },
            Snippet(symbol: "tablecells", title: String(localized: .mdTable)) { controller.requestTablePicker?() },
            Snippet(symbol: "curlybraces", title: String(localized: .mdCodeBlock)) { controller.insertCodeBlock() },
            Snippet(symbol: "minus", title: String(localized: .mdHorizontalRule)) { controller.insertBlock("---") },
            Snippet(symbol: "arrow.turn.down.left", title: String(localized: .mdLineBreak)) { controller.insertLineBreak() },
        ]

        return [
            group(representative: "textformat", inline),
            group(representative: "list.bullet.indent", lines),
            group(representative: "plus", blocks),
        ]
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        // Re-apply only when the base size actually changes; Dynamic Type
        // rescaling is handled automatically by the text view itself.
        let desiredFont = Self.scaledFont(fontSize)
        if uiView.font != desiredFont {
            uiView.font = desiredFont
        }
    }

    /// The body font scaled for the current Dynamic Type size, based on `fontSize`.
    private static func scaledFont(_ size: CGFloat) -> UIFont {
        UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: size))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PlainTextEditor
        init(_ parent: PlainTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}

/// Holds a reference to the live text view so callers can insert text at the
/// current caret / selection instead of appending to the end, and exposes the
/// Markdown editing operations used by the input-accessory toolbar.
final class PlainTextEditorController {
    fileprivate weak var textView: UITextView?

    /// Invoked when the toolbar's table button is tapped, so the host can
    /// present a row/column grid picker.
    var requestTablePicker: (() -> Void)?

    // MARK: - Primitives

    private var currentSelection: NSRange {
        guard let textView else { return NSRange(location: 0, length: 0) }
        let length = (textView.text ?? "").utf16.count
        let sel = textView.selectedRange
        let loc = min(max(sel.location, 0), length)
        return NSRange(location: loc, length: min(sel.length, length - loc))
    }

    /// Replaces `range` with `replacement`, then places the selection at `caret`.
    ///
    /// The text storage is mutated directly rather than through
    /// `UITextView.replace(_:withText:)` because the input system applies smart
    /// substitution to inserted text even when `smartDashesType` is `.no`,
    /// turning Markdown like `---` into an en/em dash.
    private func apply(_ range: NSRange, _ replacement: String, caret: NSRange) {
        guard let textView else { return }
        if !textView.isFirstResponder { textView.becomeFirstResponder() }

        // Inherit the editor's own font/colour so inserted text matches; these
        // are set in `makeUIView`, so no hard-coded fallback size is needed.
        var attributes = textView.typingAttributes
        attributes[.font] = attributes[.font] ?? textView.font
        attributes[.foregroundColor] = attributes[.foregroundColor] ?? textView.textColor ?? UIColor.label
        let attributed = NSAttributedString(string: replacement, attributes: attributes)

        let storage = textView.textStorage
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: attributed)
        storage.endEditing()

        textView.selectedRange = caret
        textView.delegate?.textViewDidChange?(textView)
    }

    /// Runs `transform` over the lines that intersect the current selection.
    private func editBlockLines(_ transform: ([String]) -> [String]) {
        guard let textView else { return }
        let ns = (textView.text ?? "") as NSString
        let sel = currentSelection
        let blockRange = ns.lineRange(for: sel)
        var lines = ns.substring(with: blockRange).components(separatedBy: "\n")
        var trailingNewline = ""
        if lines.count > 1, lines.last == "" {
            lines.removeLast()
            trailingNewline = "\n"
        }
        let newBlock = transform(lines).joined(separator: "\n") + trailingNewline
        let caret = blockRange.location + (newBlock as NSString).length
        apply(blockRange, newBlock, caret: NSRange(location: caret, length: 0))
    }

    // MARK: - Inline styles

    /// Wraps the selection in `prefix`/`suffix`, inserting `placeholder` when
    /// nothing is selected, and leaves the body text selected for easy editing.
    func wrapInline(prefix: String, suffix: String, placeholder: String) {
        guard let textView else { return }
        let ns = (textView.text ?? "") as NSString
        let sel = currentSelection
        let selected = ns.substring(with: sel)
        let body = selected.isEmpty ? placeholder : selected
        let replacement = prefix + body + suffix
        let bodyStart = sel.location + (prefix as NSString).length
        apply(sel, replacement, caret: NSRange(location: bodyStart, length: (body as NSString).length))
    }

    /// Inserts a Markdown link, selecting the placeholder the user should fill.
    func insertLink() {
        guard let textView else { return }
        let ns = (textView.text ?? "") as NSString
        let sel = currentSelection
        let selected = ns.substring(with: sel)
        let label = selected.isEmpty ? "text" : selected
        let replacement = "[\(label)](url)"
        let urlStart = sel.location + ("[\(label)](" as NSString).length
        apply(sel, replacement, caret: NSRange(location: urlStart, length: 3))
    }

    /// Inserts a hard line break (two trailing spaces plus a newline).
    func insertLineBreak() {
        let sel = currentSelection
        let replacement = "  \n"
        let caret = sel.location + (replacement as NSString).length
        apply(sel, replacement, caret: NSRange(location: caret, length: 0))
    }

    // MARK: - Line prefixes

    /// Cycles the heading level of the current line: none → # → … → ###### → none.
    func cycleHeading() {
        editBlockLines { lines in
            guard var line = lines.first else { return lines }
            var hashes = 0
            var index = line.startIndex
            while index < line.endIndex, line[index] == "#", hashes < 6 {
                hashes += 1
                index = line.index(after: index)
            }
            var body = String(line[index...])
            if body.hasPrefix(" ") { body.removeFirst() }
            let next = hashes >= 6 ? 0 : hashes + 1
            line = next == 0 ? body : String(repeating: "#", count: next) + " " + body
            var result = lines
            result[0] = line
            return result
        }
    }

    /// Toggles a per-line `prefix` (e.g. `"- "` or `"> "`) across the selection.
    func toggleLinePrefix(_ prefix: String) {
        editBlockLines { lines in
            let multi = lines.count > 1
            func skip(_ line: String) -> Bool { multi && line.trimmingCharacters(in: .whitespaces).isEmpty }
            let considered = lines.filter { !skip($0) }
            let allPrefixed = !considered.isEmpty && considered.allSatisfy { $0.hasPrefix(prefix) }
            return lines.map { line in
                if skip(line) { return line }
                if allPrefixed { return String(line.dropFirst(prefix.count)) }
                return prefix + line
            }
        }
    }

    /// Toggles an ordered list (`1.`, `2.`, …) across the selected lines.
    func toggleNumberedList() {
        editBlockLines { lines in
            let multi = lines.count > 1
            func skip(_ line: String) -> Bool { multi && line.trimmingCharacters(in: .whitespaces).isEmpty }
            func numberedPrefixLength(_ line: String) -> Int? {
                var index = line.startIndex
                var digits = 0
                while index < line.endIndex, line[index].isNumber {
                    index = line.index(after: index)
                    digits += 1
                }
                guard digits > 0, index < line.endIndex, line[index] == "." else { return nil }
                let afterDot = line.index(after: index)
                guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
                return line.distance(from: line.startIndex, to: line.index(after: afterDot))
            }
            let considered = lines.filter { !skip($0) }
            let allNumbered = !considered.isEmpty && considered.allSatisfy { numberedPrefixLength($0) != nil }
            var counter = 1
            return lines.map { line in
                if skip(line) { return line }
                if allNumbered { return String(line.dropFirst(numberedPrefixLength(line)!)) }
                defer { counter += 1 }
                return "\(counter). " + line
            }
        }
    }

    // MARK: - Blocks

    /// Inserts `block` at the caret as its own paragraph, adding surrounding
    /// blank lines only where needed. Returns `false` when no text view is
    /// attached (e.g. the editor pane is hidden), so callers can fall back.
    @discardableResult
    func insertBlock(_ block: String) -> Bool {
        guard let textView else { return false }
        let ns = (textView.text ?? "") as NSString
        let sel = currentSelection
        let start = sel.location
        let end = sel.location + sel.length
        let (prefix, suffix) = Self.padding(in: ns, start: start, end: end)
        let replacement = prefix + block + suffix
        let caret = start + (prefix + block as NSString).length
        apply(sel, replacement, caret: NSRange(location: caret, length: 0))
        return true
    }

    /// Inserts a fenced code block, placing the caret inside it.
    func insertCodeBlock() {
        guard let textView else { return }
        let ns = (textView.text ?? "") as NSString
        let sel = currentSelection
        let start = sel.location
        let end = sel.location + sel.length
        let inner = ns.substring(with: sel)
        let (prefix, suffix) = Self.padding(in: ns, start: start, end: end)
        let replacement = prefix + "```\n\(inner)\n```" + suffix
        let caret = start + (prefix + "```\n" + inner as NSString).length
        apply(sel, replacement, caret: NSRange(location: caret, length: 0))
    }

    /// Inserts a Markdown table with the given number of body `rows` and `columns`.
    func insertTable(rows: Int, columns: Int) {
        let cols = max(1, columns)
        let rws = max(1, rows)
        let header = "| " + (1...cols).map { "Column \($0)" }.joined(separator: " | ") + " |"
        let separator = "| " + Array(repeating: "---", count: cols).joined(separator: " | ") + " |"
        let bodyRow = "| " + Array(repeating: "   ", count: cols).joined(separator: " | ") + " |"
        let body = Array(repeating: bodyRow, count: rws).joined(separator: "\n")
        insertBlock([header, separator, body].joined(separator: "\n"))
    }

    /// Computes the blank-line padding needed to keep an inserted block on its
    /// own paragraph, returning the leading and trailing padding separately.
    fileprivate static func padding(in text: NSString, start: Int, end: Int) -> (String, String) {
        var prefix = ""
        var suffix = ""
        if start > 0 {
            let prev = text.substring(with: NSRange(location: start - 1, length: 1))
            if prev != "\n" {
                prefix = "\n\n"
            } else if start > 1, text.substring(with: NSRange(location: start - 2, length: 1)) != "\n" {
                prefix = "\n"
            }
        }
        if end < text.length {
            let next = text.substring(with: NSRange(location: end, length: 1))
            if next != "\n" {
                suffix = "\n\n"
            } else if end + 1 < text.length, text.substring(with: NSRange(location: end + 1, length: 1)) != "\n" {
                suffix = "\n"
            }
        }
        return (prefix, suffix)
    }
}
#endif
