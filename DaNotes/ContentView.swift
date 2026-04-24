//
//  ContentView.swift
//  DaNotes
//
//  Created by Renorari on 2025/07/03.
//

import SwiftUI
import Textual
import UniformTypeIdentifiers
import CoreGraphics
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @AppStorage("text") private var text: String = ""
    @State private var showEditor: Bool = true
    @State private var showView: Bool = true
    @State private var showClearConfirmation: Bool = false
    @AppStorage("SuppressClearConfirmation") private var suppressClearConfirmation: Bool = false
#if os(iOS)
    @State private var shareItem: ShareItem?
#endif
    @State private var exportErrorMessage: String?
    
    var body: some View {
        NavigationStack {
            HStack {
                if showEditor {
                    TextEditor(text: $text)
                        .font(.system(size: 20))
                        .textEditorStyle(.plain)
                }
                
                if showEditor && showView {
                    Divider().padding(.horizontal)
                }
                
                if showView {
                    ScrollView {
                        StructuredText(
                            markdown: text,
                            syntaxExtensions: [.math]
                        )
                            .font(.system(size: 20))
                            .textual.inlineStyle(
                                InlineStyle()
                                    .emphasis(.italic, .backgroundColor(.yellow.opacity(0.25)))
                                    .code(.monospaced, .backgroundColor(.secondary.opacity(0.25)))
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            #if os(macOS)
            .padding()
            #else
            .padding(.horizontal)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(.exportMD, systemImage: "square.and.arrow.down") {
                        exportMD()
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(.exportPDF, systemImage: "arrow.down.document") {
                        exportPDF()
                    }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarSpacer()
                ToolbarItemGroup {
                    Toggle(.showEditor, systemImage: "pencil.circle", isOn: $showEditor)
                        .keyboardShortcut("e", modifiers: .command)
                        .disabled(!showView)
                    Toggle(.showView, systemImage: "text.page", isOn: $showView)
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(!showEditor)
                }
                ToolbarSpacer()
                ToolbarItem() {
                    Button(.clearButton, systemImage: "trash") {
                        if suppressClearConfirmation || text.isEmpty {
                            text = ""
                        } else {
                            showClearConfirmation = true
                        }
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .confirmationDialog(.clearConfirm, isPresented: $showClearConfirmation) {
                        Button(.clearButton, role: .destructive) {
                            text = ""
                        }
                    }
                    .dialogIcon(Image(systemName: "trash.circle.fill"))
                    .dialogSuppressionToggle(isSuppressed: $suppressClearConfirmation)
                }
            }
#if os(iOS)
            .sheet(item: $shareItem, onDismiss: cleanUpShareURL) { item in
                ShareSheet(activityItems: [item.url]) {
                    cleanUpShareURL()
                }
            }
#endif
            .alert("PDF export failed", isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        exportErrorMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportErrorMessage ?? "")
            }
        }
    }
}

#Preview {
    ContentView()
}

private extension ContentView {
    @MainActor
    func exportPDF() {
        do {
            let pdfData = try PDFExporter.render(text: text)
#if os(macOS)
            presentSavePanel(with: pdfData, contentType: .pdf, fileExtension: "pdf")
#else
            let url = try PDFExporter.writeTemporary(data: pdfData, fileName: defaultExportFileName())
            shareItem = ShareItem(url: url)
#endif
        } catch {
            handleExportError(error)
        }
    }

    @MainActor
    func exportMD() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            handleExportError(PDFExportError.emptyContent)
            return
        }

        let data = Data(text.utf8)
#if os(macOS)
        presentSavePanel(with: data, contentType: .text, fileExtension: "md")
#else
        do {
            let url = try writeTemporaryMarkdown(data: data, fileName: defaultExportFileName())
            shareItem = ShareItem(url: url)
        } catch {
            handleExportError(error)
        }
#endif
    }

#if os(macOS)
    func presentSavePanel(with data: Data, contentType: UTType, fileExtension: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = "\(defaultExportFileName()).\(fileExtension)"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                handleExportError(error)
            }
        }
    }
#endif

    func handleExportError(_ error: Error) {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            exportErrorMessage = description
        } else {
            exportErrorMessage = error.localizedDescription
        }
    }

    func defaultExportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "DaNotes_\(formatter.string(from: Date()))"
    }

#if os(iOS)
    func writeTemporaryMarkdown(data: Data, fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).md")
        try data.write(to: url, options: .atomic)
        return url
    }

    func cleanUpShareURL() {
        if let url = shareItem?.url {
            try? FileManager.default.removeItem(at: url)
        }
        shareItem = nil
    }
#endif
}

private struct MarkdownExportView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StructuredText(
                markdown: text.isEmpty ? " " : text,
                syntaxExtensions: [.math]
            )
                .font(.system(size: 20))
                .textual.inlineStyle(
                    InlineStyle()
                        .emphasis(.italic, .backgroundColor(.yellow.opacity(0.25)))
                        .code(.monospaced, .backgroundColor(.secondary.opacity(0.25)))
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }
}

private enum PDFExportError: LocalizedError {
    case emptyContent
    case failedToCreateConsumer
    case failedToCreateContext
    case failedToWriteDocument

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Nothing to export."
        case .failedToCreateConsumer:
            return "Failed to configure the PDF writer."
        case .failedToCreateContext:
            return "Could not create the PDF graphics context."
        case .failedToWriteDocument:
            return "Could not build the PDF document."
        }
    }
}

private enum PDFExporter {
    private static var pageWidth: CGFloat = 595; // A4 Paper

    @MainActor
    static func render(text: String) throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PDFExportError.emptyContent }

        let renderer = ImageRenderer(content: MarkdownExportView(text: text))
        renderer.proposedSize = ProposedViewSize(width: pageWidth, height: nil)

        let data = NSMutableData()
        var capturedError: Error?

        renderer.render { size, render in
            do {
                var mediaBox = CGRect(origin: .zero, size: size)
                guard mediaBox.width > 0, mediaBox.height > 0 else {
                    throw PDFExportError.failedToWriteDocument
                }
                guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
                    throw PDFExportError.failedToCreateConsumer
                }

                guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                    throw PDFExportError.failedToCreateContext
                }

                defer { context.closePDF() }

                context.beginPDFPage(nil)
                render(context)
                context.endPDFPage()
            } catch {
                capturedError = error
            }
        }

        if let capturedError {
            throw capturedError
        }

        guard data.length > 0 else {
            throw PDFExportError.failedToWriteDocument
        }

        return data as Data
    }

#if os(iOS)
    static func writeTemporary(data: Data, fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
#endif
}

#if os(iOS)
private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let completion: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            completion()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Nothing to update
    }
}
#endif
