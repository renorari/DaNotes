//
//  MarkdownWebView.swift
//  DaNotes
//
//  WebKit-based Markdown renderer (marked.js + MathJax) replacing the
//  Textual/SwiftUI renderer. Handles Markdown, GFM tables and math.
//

import SwiftUI
import WebKit
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Shared resources

enum MarkdownWeb {
    /// Custom URL scheme used to serve the HTML template, bundled JS and
    /// local image attachments through a single, sandbox-friendly origin.
    static let scheme = "danotes"
    static let baseURL = URL(string: "\(scheme)://render/")!
    static let documentURL = URL(string: "\(scheme)://render/index.html")!

    /// Encodes a Swift string as a JavaScript string literal (including quotes)
    /// so it can be safely embedded as a function argument.
    static func jsStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              var string = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        if string.hasPrefix("[") { string.removeFirst() }
        if string.hasSuffix("]") { string.removeLast() }
        return string
    }
}

enum ExportError: LocalizedError {
    case emptyContent
    case pdfGenerationFailed

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return String(localized: "exportEmpty")
        case .pdfGenerationFailed:
            return String(localized: "exportPDFFailed")
        }
    }
}

// MARK: - URL scheme handler

/// Serves the rendering template and bundled JavaScript from the app bundle,
/// and image attachments from the attachments directory.
final class MarkdownSchemeHandler: NSObject, WKURLSchemeHandler {
    private let attachmentsURL: URL

    init(attachmentsURL: URL) {
        self.attachmentsURL = attachmentsURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        guard let (data, mimeType) = resolve(url: url) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(
            url: url,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Requests are fulfilled synchronously in `start`, so nothing to cancel.
    }

    private func resolve(url: URL) -> (Data, String)? {
        let path = url.path

        if path.isEmpty || path == "/" || path == "/index.html" {
            return bundleResource(named: "template.html")
        }

        if path.hasPrefix("/__assets/") {
            let name = (path as NSString).lastPathComponent
            return bundleResource(named: name)
        }

        // Everything else is treated as a local image attachment. Only the last
        // path component is used to avoid directory traversal.
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        let fileURL = attachmentsURL.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return (data, Self.mimeType(for: name))
    }

    private func bundleResource(named name: String) -> (Data, String)? {
        let nsName = name as NSString
        guard let fileURL = Bundle.main.url(
            forResource: nsName.deletingPathExtension,
            withExtension: nsName.pathExtension
        ), let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return (data, Self.mimeType(for: name))
    }

    static func mimeType(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        default:
            if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
                return mime
            }
            return "application/octet-stream"
        }
    }
}

// MARK: - Configuration factory

enum MarkdownWebConfiguration {
    static func make(attachmentsURL: URL) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            MarkdownSchemeHandler(attachmentsURL: attachmentsURL),
            forURLScheme: MarkdownWeb.scheme
        )
        return configuration
    }
}

// MARK: - SwiftUI preview view

struct MarkdownWebView {
    let markdown: String
    let attachmentsURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(attachmentsURL: attachmentsURL)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let webView: WKWebView
        private var isLoaded = false
        private var pendingMarkdown: String?
        private var lastRendered: String?

        init(attachmentsURL: URL) {
            let configuration = MarkdownWebConfiguration.make(attachmentsURL: attachmentsURL)
            webView = WKWebView(frame: .zero, configuration: configuration)
            super.init()
            webView.navigationDelegate = self
            // Let the SwiftUI background show through so the rendered content
            // blends with the window instead of using WebKit's own (slightly
            // different) system background, which is visible in dark mode.
#if os(iOS)
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
            webView.scrollView.keyboardDismissMode = .interactive
#else
            webView.setValue(false, forKey: "drawsBackground")
#endif
            webView.load(URLRequest(url: MarkdownWeb.documentURL))
        }

        func update(markdown: String) {
            pendingMarkdown = markdown
            guard isLoaded else { return }
            renderPending()
        }

        private func renderPending() {
            guard let markdown = pendingMarkdown, markdown != lastRendered else { return }
            lastRendered = markdown
            let literal = MarkdownWeb.jsStringLiteral(markdown)
            webView.evaluateJavaScript("window.__daNotesRender(\(literal));", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            renderPending()
        }
    }
}

#if os(macOS)
extension MarkdownWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.update(markdown: markdown)
    }
}
#else
extension MarkdownWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.update(markdown: markdown)
    }
}
#endif

// MARK: - PDF export

/// Renders Markdown into an A4, paginated PDF using an off-screen `WKWebView`.
///
/// The same template/renderer as the live preview is reused, so Markdown, GFM
/// tables and MathJax math all appear exactly as on screen. Pagination and page
/// margins come from the `@page` rules in `styles.css`, honoured by WebKit's
/// print engine (`NSPrintOperation` on macOS, `UIPrintPageRenderer` on iOS).
@MainActor
final class MarkdownPDFExporter: NSObject {
    /// A4 in PostScript points (72 dpi): 210mm × 297mm.
    private static let a4 = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)

    private let webView: WKWebView
    private let markdown: String
    private var completion: (@MainActor (Result<Data, Error>) -> Void)?

    /// Keeps the exporter alive while the asynchronous render is in flight.
    private static var liveExporters = Set<MarkdownPDFExporter>()

#if os(macOS)
    /// Off-screen host window. WKWebView printing hangs unless the view is part
    /// of a window's view hierarchy and the operation is run modally for it.
    private var hostWindow: NSWindow?
    private var pdfOutputURL: URL?
#endif

    init(markdown: String, attachmentsURL: URL) {
        self.markdown = markdown
        let configuration = MarkdownWebConfiguration.make(attachmentsURL: attachmentsURL)
        webView = WKWebView(frame: Self.a4, configuration: configuration)
        super.init()
        configuration.userContentController.add(self, name: "rendered")
        webView.navigationDelegate = self
#if os(macOS)
        // Host the web view in an off-screen window so print rendering works.
        let window = NSWindow(
            contentRect: Self.a4,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        hostWindow = window
#endif
    }

    /// Renders the Markdown and delivers the resulting PDF data on the main actor.
    func export(completion: @escaping @MainActor (Result<Data, Error>) -> Void) {
        self.completion = completion
        Self.liveExporters.insert(self)
        webView.load(URLRequest(url: MarkdownWeb.documentURL))
    }

    private func finish(_ result: Result<Data, Error>) {
        guard completion != nil else { return }
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.stopLoading()
#if os(macOS)
        hostWindow?.contentView = nil
        hostWindow = nil
#endif
        completion?(result)
        completion = nil
        Self.liveExporters.remove(self)
    }

    /// Produces the paginated PDF once the web content has finished rendering.
    private func generatePDF() {
#if os(macOS)
        guard let window = hostWindow else {
            finish(.failure(ExportError.pdfGenerationFailed))
            return
        }

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: Self.a4.width, height: Self.a4.height)
        // Page margins are supplied by the `@page` rule in the stylesheet, so
        // keep the print margins at zero to avoid doubling them up.
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = outputURL
        pdfOutputURL = outputURL

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = NSRect(origin: .zero, size: printInfo.paperSize)

        // Run modally for the off-screen window. Unlike `run()`, this variant
        // does not spin a nested run loop, so it does not deadlock WebKit.
        operation.runModal(
            for: window,
            delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
#else
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        // Full-page paper/printable area; page margins come from the `@page`
        // rule so they repeat on every page.
        renderer.setValue(Self.a4, forKey: "paperRect")
        renderer.setValue(Self.a4, forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, Self.a4, nil)
        let pageCount = renderer.numberOfPages
        for page in 0..<pageCount {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()

        guard data.length > 0, pageCount > 0 else {
            finish(.failure(ExportError.pdfGenerationFailed))
            return
        }
        finish(.success(data as Data))
#endif
    }

#if os(macOS)
    // The print system may invoke this delegate selector on a background thread,
    // so it must be `nonisolated`; hop back to the main actor before touching the
    // web view or delivering the result.
    @objc nonisolated private func printOperationDidRun(
        _ printOperation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        Task { @MainActor [weak self] in
            self?.handlePrintCompletion(success: success)
        }
    }

    @MainActor
    private func handlePrintCompletion(success: Bool) {
        let outputURL = pdfOutputURL
        pdfOutputURL = nil
        defer { outputURL.map { try? FileManager.default.removeItem(at: $0) } }

        guard success, let outputURL, let data = try? Data(contentsOf: outputURL), !data.isEmpty else {
            finish(.failure(ExportError.pdfGenerationFailed))
            return
        }
        finish(.success(data))
    }
#endif
}

extension MarkdownPDFExporter: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Add the `pdf` body class (opaque white background) and render.
        let literal = MarkdownWeb.jsStringLiteral(markdown)
        webView.evaluateJavaScript(
            "document.body.classList.add('pdf'); window.__daNotesRender(\(literal));",
            completionHandler: nil
        )
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }
}

extension MarkdownPDFExporter: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "rendered" else { return }
        // The `rendered` message fires once Markdown + MathJax are typeset. Wait
        // for any image attachments to decode, then capture on the next runloop
        // so the final layout is flushed before printing.
        let waitForImages = """
        (async () => {
          const images = Array.from(document.images);
          await Promise.all(images.map(img => img.complete
            ? null
            : new Promise(resolve => { img.onload = img.onerror = resolve; })));
          return true;
        })()
        """
        webView.evaluateJavaScript(waitForImages) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.generatePDF()
            }
        }
    }
}
