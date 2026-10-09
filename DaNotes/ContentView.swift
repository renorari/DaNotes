//
//  ContentView.swift
//  DaNotes
//
//  Created by Renorari on 2025/07/03.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Bindable var note: Note
    var outlineJump: OutlineJump? = nil
    /// Invoked with a tag's text (without `#`) when the user taps a hashtag
    /// chip in the preview, so the sidebar can filter by it.
    var onHashtagTapped: ((String) -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var showEditor: Bool = true
    @State private var showView: Bool = true
    @State private var showImagePicker: Bool = false
    @State private var showHandwriting: Bool = false
    @State private var showHistory: Bool = false
    @State private var pendingConflict: RevisionStore.PendingConflict?
    @State private var commitTask: Task<Void, Never>?
#if os(iOS)
    @State private var showTablePicker: Bool = false
    @State private var markupTarget: MarkupTarget?
#endif
#if os(iOS)
    @State private var shareItem: ShareItem?
    @State private var selectedPhotoItem: PhotosPickerItem?
#endif
    @State private var exportErrorMessage: String?
    @State private var imageImportErrorMessage: String?
    @State private var editorController = PlainTextEditorController()
    @State private var markdownViewController = MarkdownWebViewController()

    private var text: String {
        get { note.text }
        nonmutating set {
            note.text = newValue
            note.modifiedAt = Date()
        }
    }

    private var attachmentStore: ImageAttachmentStore {
        ImageAttachmentStore(context: modelContext)
    }

    var body: some View {
        NavigationStack {
            HStack {
                if showEditor {
                    PlainTextEditor(text: Binding(get: { text }, set: { text = $0 }), controller: editorController)
                }
                
                if showEditor && showView {
                    Divider().padding(.horizontal)
                }
                
                if showView {
                    MarkdownWebView(markdown: text, attachmentData: { [modelContext] name in
                        ImageAttachmentStore(context: modelContext).data(named: name)
                    }, controller: markdownViewController)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            #if os(macOS)
            .padding()
            #else
            .padding(.horizontal)
            #endif
            // Attachments synced from another device can land after the text
            // that references them; refetch so they appear once they arrive.
            .onChange(of: note.attachments?.count) {
                markdownViewController.refreshAttachments()
            }
            // `task(id:)` rather than `onChange` so a jump requested while this
            // view was being created (compact layouts) still applies.
            .task(id: outlineJump) {
                guard let item = outlineJump?.item else { return }
                editorController.reveal(location: item.location)
                markdownViewController.scrollToHeading(at: item.index)
            }
            .onDrop(of: [.image], isTargeted: nil) { providers in
                handleImageDrop(providers)
            }
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
                    Button(.copyImage, systemImage: "photo.on.rectangle") {
                        copyImage()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarSpacer()
                ToolbarItemGroup {
                    Button(.addImage, systemImage: "photo.badge.plus") {
                        showImagePicker = true
                    }
#if os(iOS)
                    Button(.handwriting, systemImage: "pencil.and.scribble") {
                        showHandwriting = true
                    }
#endif
                    Button(.noteHistory, systemImage: "clock.arrow.circlepath") {
                        showHistory = true
                    }
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
            }
#if os(iOS)
            .sheet(item: $shareItem, onDismiss: cleanUpShareURL) { item in
                ShareSheet(activityItems: [item.url]) {
                    cleanUpShareURL()
                }
            }

            .photosPicker(
                isPresented: $showImagePicker,
                selection: $selectedPhotoItem,
                matching: .images,
                preferredItemEncoding: .current
            )
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await importImage(from: newItem)
                }
            }
#endif
#if os(macOS)
            .fileImporter(isPresented: $showImagePicker, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importImage(from: url)
                case .failure(let error):
                    handleImageImportError(error)
                }
            }
#endif
            .alert(.importImageError, isPresented: Binding(
                get: { imageImportErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        imageImportErrorMessage = nil
                    }
                }
            )) {
                Button(.ok, role: .cancel) { }
            } message: {
                Text(imageImportErrorMessage ?? "")
            }
            .alert(.exportError, isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        exportErrorMessage = nil
                    }
                }
            )) {
                Button(.ok, role: .cancel) { }
            } message: {
                Text(exportErrorMessage ?? "")
            }
#if os(iOS)
            .sheet(isPresented: $showHandwriting) {
                HandwritingSheet { pngData in
                    insertPNGImage(pngData)
                }
            }
            .sheet(isPresented: $showTablePicker) {
                TableGridPicker { rows, columns in
                    editorController.insertTable(rows: rows, columns: columns)
                    showTablePicker = false
                }
                .presentationSizing(.fitted)
            }
            .sheet(item: $markupTarget) { target in
                HandwritingSheet(backgroundImage: target.image) { data in
                    saveMarkup(data, fileName: target.fileName)
                }
            }
            .onAppear {
                editorController.requestTablePicker = { showTablePicker = true }
                markdownViewController.onImageTapped = { fileName in
                    presentMarkup(for: fileName)
                }
            }
#endif
            .onAppear {
                editorController.onImagePaste = { data, fileExtension in
                    insertPastedImage(data, fileExtension: fileExtension)
                }
                markdownViewController.onHashtagTapped = { tag in
                    onHashtagTapped?(tag)
                }
            }
            .sheet(isPresented: $showHistory) {
                HistoryView(note: note)
            }
            .sheet(item: $pendingConflict) { conflict in
                ConflictResolutionView(note: note, conflict: conflict)
            }
            // Revisions set up the "never silently lose edits" safety net:
            // periodic auto-commits while typing, a flush when leaving the
            // note or backgrounding the app, and a merge check whenever
            // sync brings in another device's revisions.
            .onAppear {
                reconcileIfNeeded()
            }
            .onDisappear {
                commitTask?.cancel()
                RevisionStore.commit(note: note, context: modelContext)
            }
            .onChange(of: note.text) {
                commitTask?.cancel()
                commitTask = Task {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    RevisionStore.commit(note: note, context: modelContext)
                }
            }
            .onChange(of: note.revisions?.count) {
                reconcileIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    commitTask?.cancel()
                    RevisionStore.commit(note: note, context: modelContext)
                }
            }
        }
    }

    @MainActor
    private func reconcileIfNeeded() {
        if let conflict = RevisionStore.reconcile(note: note, context: modelContext) {
            pendingConflict = conflict
        }
    }
}

#Preview {
    ContentView(note: Note(text: "# DaNotes"))
        .modelContainer(for: Note.self, inMemory: true)
}

private extension ContentView {
    @MainActor
    func exportMD() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            handleExportError(ExportError.emptyContent)
            return
        }

        let data = Data(text.utf8)
#if os(macOS)
        presentSavePanel(with: data, contentType: .text, fileExtension: "md")
#else
        do {
            let url = try writeTemporaryFile(data: data, fileName: defaultExportFileName(), fileExtension: "md")
            shareItem = ShareItem(url: url)
        } catch {
            handleExportError(error)
        }
#endif
    }

    @MainActor
    func exportPDF() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            handleExportError(ExportError.emptyContent)
            return
        }

        let exporter = MarkdownPDFExporter(
            markdown: text,
            attachmentData: { [modelContext] name in
                ImageAttachmentStore(context: modelContext).data(named: name)
            }
        )
        exporter.export { result in
            switch result {
            case .success(let data):
#if os(macOS)
                presentSavePanel(with: data, contentType: .pdf, fileExtension: "pdf")
#else
                do {
                    let url = try writeTemporaryFile(data: data, fileName: defaultExportFileName(), fileExtension: "pdf")
                    shareItem = ShareItem(url: url)
                } catch {
                    handleExportError(error)
                }
#endif
            case .failure(let error):
                handleExportError(error)
            }
        }
    }

    @MainActor
    func copyImage() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            handleExportError(ExportError.emptyContent)
            return
        }

        let exporter = MarkdownImageExporter(
            markdown: text,
            attachmentData: { [modelContext] name in
                ImageAttachmentStore(context: modelContext).data(named: name)
            }
        )
        exporter.export { result in
            switch result {
            case .success(let data):
                copyImageDataToPasteboard(data)
            case .failure(let error):
                handleExportError(error)
            }
        }
    }

    @MainActor
    func copyImageDataToPasteboard(_ data: Data) {
#if os(macOS)
        guard let image = NSImage(data: data) else {
            handleExportError(ExportError.imageGenerationFailed)
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
#else
        guard let image = UIImage(data: data) else {
            handleExportError(ExportError.imageGenerationFailed)
            return
        }
        UIPasteboard.general.image = image
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

    func handleImageImportError(_ error: Error) {
        imageImportErrorMessage = error.localizedDescription
    }

    func insertImageMarkdown(relativePath: String) {
        let imageMarkdown = "![image](\(relativePath))"

        // Insert at the caret when the editor is available; otherwise append.
        if editorController.insertBlock(imageMarkdown) {
            return
        }

        if text.isEmpty {
            text = imageMarkdown
        } else if text.hasSuffix("\n") {
            text += imageMarkdown
        } else {
            text += "\n\n\(imageMarkdown)"
        }
    }

    func insertPNGImage(_ data: Data) {
        insertPastedImage(data, fileExtension: "png")
    }

    /// Stores raw image data (e.g. pasted from the system clipboard) as an
    /// attachment and inserts the corresponding Markdown at the caret.
    func insertPastedImage(_ data: Data, fileExtension: String) {
        let fileName = attachmentStore.store(data, fileExtension: fileExtension, in: note)
        insertImageMarkdown(relativePath: fileName)
    }

    /// Handles images dragged into the window from Finder, Photos, Safari,
    /// etc. Recognises common image types up front to keep their original
    /// format; anything else that merely conforms to `.image` still gets
    /// accepted and stored as PNG.
    @MainActor
    @discardableResult
    func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        let orderedTypes: [(UTType, String)] = [(.png, "png"), (.jpeg, "jpg"), (.gif, "gif"), (.tiff, "tiff"), (.heic, "heic")]
        var handledAny = false
        for provider in providers {
            let match = orderedTypes.first { provider.hasItemConformingToTypeIdentifier($0.0.identifier) }
            guard let typeIdentifier = match?.0.identifier
                ?? (provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ? UTType.image.identifier : nil) else {
                continue
            }
            let fileExtension = match?.1 ?? "png"
            handledAny = true
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    insertPastedImage(data, fileExtension: fileExtension)
                }
            }
        }
        return handledAny
    }

    func importImage(from url: URL) {
        let didStartAccessingResource = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessingResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let fileName = try attachmentStore.storeCopiedImage(from: url, in: note)
            insertImageMarkdown(relativePath: fileName)
        } catch {
            handleImageImportError(error)
        }
    }

#if os(iOS)
    @MainActor
    func importImage(from photoItem: PhotosPickerItem) async {
        defer {
            selectedPhotoItem = nil
        }

        do {
            guard let data = try await photoItem.loadTransferable(type: Data.self) else {
                throw NSError(domain: "DaNotes.ImageImport", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not read the selected photo."])
            }

            let ext = photoItem.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let fileName = attachmentStore.store(data, fileExtension: ext, in: note)
            insertImageMarkdown(relativePath: fileName)
        } catch {
            handleImageImportError(error)
        }
    }

    /// Loads the tapped attachment and presents it for markup.
    @MainActor
    func presentMarkup(for fileName: String) {
        guard let data = attachmentStore.data(named: fileName), let image = UIImage(data: data) else { return }
        markupTarget = MarkupTarget(fileName: fileName, image: image)
    }

    /// Overwrites the original attachment with the annotated version, then
    /// tells the preview to refetch it (it would otherwise keep showing the
    /// bytes it already decoded for that unchanged URL).
    @MainActor
    func saveMarkup(_ data: Data, fileName: String) {
        guard let attachment = attachmentStore.attachment(named: fileName) else { return }
        attachment.data = data
        note.modifiedAt = Date()
        markdownViewController.refreshAttachments()
    }
#endif

    func defaultExportFileName() -> String {
        if let title = note.headingTitle {
            let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
            let sanitized = title.components(separatedBy: invalid).joined(separator: "_")
                .trimmingCharacters(in: .whitespaces)
            if !sanitized.isEmpty { return String(sanitized.prefix(100)) }
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "DaNotes_\(formatter.string(from: Date()))"
    }

#if os(iOS)
    func writeTemporaryFile(data: Data, fileName: String, fileExtension: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).\(fileExtension)")
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

#if os(iOS)
private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// An attachment image the user tapped in the preview, on its way to the
/// markup sheet.
private struct MarkupTarget: Identifiable {
    let fileName: String
    let image: UIImage
    var id: String { fileName }
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
