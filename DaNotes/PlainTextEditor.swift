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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

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
#endif

#if os(iOS)
import UIKit

struct PlainTextEditor: UIViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 20

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
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
#endif
