//
//  ContentView.swift
//  DaNotes
//
//  Created by Renorari on 2025/07/03.
//

import SwiftUI
import Textual
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import UIKit
#endif

struct ContentView: View {
    @AppStorage("text") private var text: String = ""
    @State private var showEditor: Bool = true
    @State private var showView: Bool = true
    @State private var showClearConfirmation: Bool = false
    @State private var showImagePicker: Bool = false
    @AppStorage("SuppressClearConfirmation") private var suppressClearConfirmation: Bool = false
#if os(iOS)
    @State private var shareItem: ShareItem?
    @State private var selectedPhotoItem: PhotosPickerItem?
#endif
    @State private var exportErrorMessage: String?
    @State private var imageImportErrorMessage: String?
    
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
                        MarkdownText(markdown: text, baseURL: ImageAttachmentStore.shared.baseURL)
                            .id(text)
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
                }
                ToolbarSpacer()
                ToolbarItemGroup {
                    Button(.addImage, systemImage: "photo.badge.plus") {
                        showImagePicker = true
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
                ToolbarSpacer()
                ToolbarItem() {
                    Button(.clearButton, systemImage: "trash") {
                        if suppressClearConfirmation || text.isEmpty {
                            clearAllContent()
                        } else {
                            showClearConfirmation = true
                        }
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .confirmationDialog(.clearConfirm, isPresented: $showClearConfirmation) {
                        Button(.clearButton, role: .destructive) {
                            clearAllContent()
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
            .alert("Image import failed", isPresented: Binding(
                get: { imageImportErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        imageImportErrorMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(imageImportErrorMessage ?? "")
            }
        }
    }
}

#Preview {
    ContentView()
}

private extension ContentView {
    @MainActor
    func exportMD() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            handleExportError(NSError(domain: "DaNotes.Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nothing to export."]))
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

    func handleImageImportError(_ error: Error) {
        imageImportErrorMessage = error.localizedDescription
    }

    func insertImageMarkdown(relativePath: String) {
        let imageMarkdown = "![image](\(relativePath))"

        if text.isEmpty {
            text = imageMarkdown
        } else if text.hasSuffix("\n") {
            text += imageMarkdown
        } else {
            text += "\n\n\(imageMarkdown)"
        }
    }

    func importImage(from url: URL) {
        let didStartAccessingResource = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessingResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let storedURL = try ImageAttachmentStore.shared.storeCopiedImage(from: url)
            insertImageMarkdown(relativePath: storedURL.lastPathComponent)
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
            let storedURL = try ImageAttachmentStore.shared.storeImageData(data, fileExtension: ext)
            insertImageMarkdown(relativePath: storedURL.lastPathComponent)
        } catch {
            handleImageImportError(error)
        }
    }
#endif

    func clearAllContent() {
        text = ""
        ImageAttachmentStore.shared.removeAllAttachments()
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

private struct MarkdownText: View {
    let markdown: String
    let baseURL: URL

    var body: some View {
        StructuredText(markdown: markdown, baseURL: baseURL, syntaxExtensions: [.math])
            .textual.imageAttachmentLoader(.image(relativeTo: baseURL))
            .font(.system(size: 20))
            .textual.inlineStyle(
                InlineStyle()
                    .emphasis(.italic, .backgroundColor(.yellow.opacity(0.25)))
                    .code(.monospaced, .backgroundColor(.secondary.opacity(0.25)))
            )
    }
}

private struct ImageAttachmentStore {
    static let shared = ImageAttachmentStore()

    let baseURL: URL

    private init() {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let attachmentsDirectory = supportDirectory
            .appendingPathComponent("DaNotes", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)

        try? fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        self.baseURL = attachmentsDirectory
    }

    func storeCopiedImage(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let extensionValue = sourceURL.pathExtension
        let fileName = extensionValue.isEmpty
            ? UUID().uuidString
            : "\(UUID().uuidString).\(extensionValue.lowercased())"
        let destinationURL = baseURL.appendingPathComponent(fileName)

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    func storeImageData(_ data: Data, fileExtension: String) throws -> URL {
        let normalizedExtension = fileExtension.lowercased()
        let fileName = normalizedExtension.isEmpty
            ? UUID().uuidString
            : "\(UUID().uuidString).\(normalizedExtension)"
        let destinationURL = baseURL.appendingPathComponent(fileName)

        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    func removeAllAttachments() {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in urls {
            try? fileManager.removeItem(at: url)
        }
    }
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
