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

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return String(localized: "exportEmpty")
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
#if os(iOS)
            webView.scrollView.keyboardDismissMode = .interactive
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
