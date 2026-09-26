//
//  HandwritingCanvasView.swift
//  DaNotes
//
//  A PencilKit-based sheet for iPad: Apple Pencil (and finger) input with the
//  system tool picker. Used two ways:
//  - Handwriting: a blank white canvas, rasterized to a PNG and handed back
//    for insertion as a new attachment.
//  - Markup: an existing image is shown as a fixed background and the
//    drawing is composited onto it at the image's own resolution, so an
//    existing attachment can be annotated in place.
//
//  Handwriting/markup is iPad-only; on macOS the toolbar offers screenshot
//  capture instead (see ScreenshotCapture.swift).
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

    /// Produces the finished PNG: freehand strokes rasterized on white, or
    /// (when `background` is supplied) the strokes composited onto that
    /// image at its own resolution, for in-place markup of an existing image.
    func makePNG(background: UIImage? = nil) -> Data? {
        guard let canvas else { return nil }
        if let background {
            return canvas.drawing.rasterizedPNG(onto: background, canvasSize: canvas.bounds.size)
        }
        return canvas.drawing.rasterizedPNG()
    }

    func clear() {
        canvas?.drawing = PKDrawing()
        isEmpty = true
    }
}

struct HandwritingSheet: View {
    /// When set, this image is shown as a fixed background and the finished
    /// drawing is composited onto it (markup); when `nil`, the canvas is a
    /// plain white background (freehand handwriting).
    var backgroundImage: UIImage? = nil
    /// Called with PNG data when the user confirms a non-empty drawing.
    var onComplete: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = HandwritingController()

    var body: some View {
        NavigationStack {
            Group {
                if let backgroundImage {
                    ZStack {
                        Image(uiImage: backgroundImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                        HandwritingCanvasRepresentable(controller: controller, isOpaque: false)
                            .aspectRatio(backgroundImage.size, contentMode: .fit)
                    }
                } else {
                    HandwritingCanvasRepresentable(controller: controller, isOpaque: true)
                        .background(Color.white)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle(backgroundImage == nil ? Text(.handwriting) : Text(.markup))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.cancel) { dismiss() }
                        // Explicit, since the canvas holding first responder
                        // otherwise swallows a plain Escape/Return before it
                        // reaches the toolbar's automatic shortcut handling.
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(backgroundImage == nil ? .insertButton : .saveButton) {
                        if let data = controller.makePNG(background: backgroundImage) {
                            onComplete(data)
                        }
                        dismiss()
                    }
                    .disabled(controller.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        // Once there's a drawing, a stray tap outside the sheet (or a swipe)
        // must not discard it; only the explicit Cancel/Insert buttons close it.
        .interactiveDismissDisabled(!controller.isEmpty)
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
    /// `true` for freehand handwriting (opaque white canvas); `false` for
    /// markup, where the canvas must be transparent so the background image
    /// underneath shows through.
    var isOpaque: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(controller) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = HandwritingCanvas()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = isOpaque ? .white : .clear
        canvas.isOpaque = isOpaque
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

    /// Composites the drawing onto `background` at the image's own pixel
    /// resolution, so annotating an existing attachment keeps its original
    /// size. `canvasSize` is the on-screen canvas view's bounds (points) the
    /// strokes were drawn in, used to scale them up to that resolution.
    func rasterizedPNG(onto background: UIImage, canvasSize: CGSize) -> Data? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let outputSize = CGSize(width: max(background.size.width, 1), height: max(background.size.height, 1))
        let scale = outputSize.width / canvasSize.width

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let image = renderer.image { _ in
            background.draw(in: CGRect(origin: .zero, size: outputSize))
            self.image(from: CGRect(origin: .zero, size: canvasSize), scale: scale)
                .draw(in: CGRect(origin: .zero, size: outputSize))
        }
        return image.pngData()
    }
}
#endif
