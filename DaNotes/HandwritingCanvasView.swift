//
//  HandwritingCanvasView.swift
//  DaNotes
//
//  A PencilKit-based handwriting sheet for iPad: Apple Pencil (and finger)
//  input with the system tool picker. The finished drawing is rasterized to a
//  PNG on a white background and handed back to the caller for insertion.
//
//  Handwriting is iPad-only; on macOS the toolbar offers screenshot capture
//  instead (see ScreenshotCapture.swift).
//

#if os(iOS)
import SwiftUI
import Combine
import UIKit
import PencilKit

/// Bridges the PencilKit canvas to the SwiftUI sheet: exposes whether the
/// canvas is empty (to enable/disable "Insert") and produces the final PNG.
final class HandwritingController: ObservableObject {
    @Published var isEmpty: Bool = true
    weak var canvas: PKCanvasView?

    func makePNG() -> Data? { canvas?.drawing.rasterizedPNG() }

    func clear() {
        canvas?.drawing = PKDrawing()
        isEmpty = true
    }
}

struct HandwritingSheet: View {
    /// Called with PNG data when the user confirms a non-empty drawing.
    var onComplete: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = HandwritingController()

    var body: some View {
        NavigationStack {
            HandwritingCanvasRepresentable(controller: controller)
                .background(Color.white)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(.handwriting)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(.cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(.insertButton) {
                            if let data = controller.makePNG() {
                                onComplete(data)
                            }
                            dismiss()
                        }
                        .disabled(controller.isEmpty)
                    }
                }
        }
    }
}

/// A `PKCanvasView` that shows the system tool picker and becomes first
/// responder once it is in a window.
private final class HandwritingCanvas: PKCanvasView {
    private let toolPicker = PKToolPicker()

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        drawingPolicy = .anyInput
        toolPicker.setVisible(true, forFirstResponder: self)
        toolPicker.addObserver(self)
        becomeFirstResponder()
    }
}

struct HandwritingCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var controller: HandwritingController

    func makeCoordinator() -> Coordinator { Coordinator(controller) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = HandwritingCanvas()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.tool = PKInkingTool(.pen, color: .black, width: 5)
        controller.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {}

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let controller: HandwritingController
        init(_ controller: HandwritingController) { self.controller = controller }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            controller.isEmpty = canvasView.drawing.strokes.isEmpty
        }
    }
}

private extension PKDrawing {
    /// Rasterizes onto a white background, cropped to content (with a margin).
    func rasterizedPNG(scale: CGFloat = 2) -> Data? {
        let content = bounds
        guard content.width > 1, content.height > 1 else { return nil }
        let rect = content.insetBy(dx: -16, dy: -16)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: rect.size))
            self.image(from: rect, scale: scale)
                .draw(in: CGRect(origin: .zero, size: rect.size))
        }
        return image.pngData()
    }
}
#endif
