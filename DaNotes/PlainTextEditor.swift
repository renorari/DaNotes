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
        textView.font = .systemFont(ofSize: fontSize)
        textView.backgroundColor = .clear

        // Disable the smart substitutions.
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no

        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.font?.pointSize != fontSize {
            uiView.font = .systemFont(ofSize: fontSize)
        }
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
/// current caret / selection instead of appending to the end.
final class PlainTextEditorController {
    fileprivate weak var textView: UITextView?

    /// Inserts `block` at the caret as its own paragraph, adding surrounding
    /// blank lines only where needed. Returns `false` when no text view is
    /// attached (e.g. the editor pane is hidden), so callers can fall back.
    @discardableResult
    func insertBlock(_ block: String) -> Bool {
        guard let textView else { return false }
        let ns = (textView.text ?? "") as NSString
        let selection = textView.selectedRange
        let start = min(max(selection.location, 0), ns.length)
        let end = min(start + selection.length, ns.length)
        let padded = Self.paddedBlock(block, in: ns, start: start, end: end)

        if let from = textView.position(from: textView.beginningOfDocument, offset: start),
           let to = textView.position(from: textView.beginningOfDocument, offset: end),
           let range = textView.textRange(from: from, to: to) {
            textView.replace(range, withText: padded)
            textView.delegate?.textViewDidChange?(textView)
            return true
        }
        return false
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
