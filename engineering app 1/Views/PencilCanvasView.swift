//
//  PencilCanvasView.swift
//  Tolerance
//
//  SwiftUI wrapper around PencilKit's PKCanvasView. Loads/saves a page's ink,
//  shows the system tool picker, and (Phase 4) watches for a "circle gesture":
//  a closed loop drawn around existing ink. When detected, the loop is treated
//  as a transient gesture — removed from the ink — and reported upward so the
//  UI can show the "Ask AI" popup.
//

#if os(iOS)
import SwiftUI
import PencilKit

/// A detected circle gesture, expressed in the canvas view's coordinate space
/// (points), plus a rasterized image of the enclosed content for OCR.
struct CircleGesture: Identifiable {
    let id = UUID()
    /// Where to anchor the popup (top-center of the loop).
    let anchorInView: CGPoint
    /// Where to draw the transient highlight.
    let highlightRectInView: CGRect
    /// White-backed image of the enclosed ink, ready for text recognition.
    let croppedImage: UIImage
}

struct PencilCanvasView: UIViewRepresentable {
    let page: Page
    /// Fired when a circle gesture around ink is recognized.
    var onCircleDetected: (CircleGesture) -> Void = { _ in }
    /// Fired when the user draws ordinary ink (used to dismiss a stale popup).
    var onOrdinaryStroke: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        canvas.alwaysBounceVertical = true
        canvas.backgroundColor = .systemBackground

        if let drawing = try? PKDrawing(data: page.drawingData) {
            canvas.drawing = drawing
        }
        context.coordinator.canvas = canvas

        let toolPicker = PKToolPicker()
        toolPicker.addObserver(canvas)
        toolPicker.setVisible(true, forFirstResponder: canvas)
        context.coordinator.toolPicker = toolPicker
        DispatchQueue.main.async { canvas.becomeFirstResponder() }

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        weak var canvas: PKCanvasView?
        var toolPicker: PKToolPicker?

        private var hasLoaded = false
        /// Guards against reacting to our own programmatic edits (loop removal).
        private var isEditingProgrammatically = false

        init(_ parent: PencilCanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard hasLoaded else { hasLoaded = true; return }
            guard !isEditingProgrammatically else { return }

            let drawing = canvasView.drawing

            // Is the newest stroke a loop around existing ink?
            if let result = CircleGestureDetector.detect(in: drawing), result.hasEnclosedInk {
                handleCircleGesture(result, on: canvasView, drawing: drawing)
            } else {
                save(drawing)
                parent.onOrdinaryStroke()
            }
        }

        // MARK: - Circle gesture

        private func handleCircleGesture(_ result: CircleGestureResult,
                                         on canvasView: PKCanvasView,
                                         drawing: PKDrawing) {
            // Remove the loop stroke so it's never committed as ink.
            let cleaned = CircleGestureDetector.removingLoop(result, from: drawing)
            isEditingProgrammatically = true
            canvasView.drawing = cleaned
            isEditingProgrammatically = false
            save(cleaned)

            // Rasterize the enclosed content (white background) for OCR.
            let padding: CGFloat = 16
            let contentRect = result.contentRect.insetBy(dx: -padding, dy: -padding)
            let image = DrawingRasterizer.whiteBackedImage(from: cleaned, rect: contentRect, scale: 3)

            // Convert loop bounds from drawing space to view space for the UI.
            let zoom = canvasView.zoomScale
            let offset = canvasView.contentOffset
            func toView(_ p: CGPoint) -> CGPoint {
                CGPoint(x: p.x * zoom - offset.x, y: p.y * zoom - offset.y)
            }
            let loopRect = result.loopRect
            let viewRect = CGRect(x: loopRect.minX * zoom - offset.x,
                                  y: loopRect.minY * zoom - offset.y,
                                  width: loopRect.width * zoom,
                                  height: loopRect.height * zoom)
            let anchor = CGPoint(x: viewRect.midX, y: max(viewRect.minY, 8))

            let gesture = CircleGesture(anchorInView: anchor,
                                        highlightRectInView: viewRect,
                                        croppedImage: image)
            parent.onCircleDetected(gesture)
            _ = toView // silence unused in case of future use
        }

        private func save(_ drawing: PKDrawing) {
            parent.page.drawingData = drawing.dataRepresentation()
            parent.page.notepad?.markEdited()
        }
    }
}

/// Renders a PKDrawing region onto a white background so Vision's text
/// recognizer sees dark ink on a light field.
enum DrawingRasterizer {
    static func whiteBackedImage(from drawing: PKDrawing, rect: CGRect, scale: CGFloat) -> UIImage {
        let inkImage = drawing.image(from: rect, scale: scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: rect.size))
            inkImage.draw(in: CGRect(origin: .zero, size: rect.size))
        }
    }
}
#endif
