//
//  PencilCanvasView.swift
//  Tolerance
//
//  The infinite, grid-lined PencilKit canvas.
//
//  • Scrolls vertically forever — the page grows downward as you reach the
//    bottom, so "the next page is below the last".
//  • Draws a grid behind the ink (ink always renders above the grid).
//  • Paper color, grid spacing, and pen (auto-opposite-of-paper) come from the
//    notepad's settings.
//  • Pencil draws; a finger scrolls or long-presses (long-press selects a
//    problem for the pill menu).
//  • Reports drawing start/stop so the toolbar can hide while writing, and
//    reports circle gestures / long-press selections upward.
//
//  iOS/iPadOS only.
//

#if os(iOS)
import SwiftUI
import PencilKit

/// A region of ink selected by a gesture (circle or long-press), expressed in
/// the canvas view's coordinate space, with a rasterized image for OCR.
struct InkSelection: Identifiable {
    let id = UUID()
    let anchorInView: CGPoint
    let highlightRectInView: CGRect
    let croppedImage: UIImage
}

struct PencilCanvasView: UIViewRepresentable {
    let page: Page

    // Appearance (from the notepad settings).
    let paperColorHex: String
    let gridSpacing: Double
    let showsGrid: Bool

    // Tool state, driven by the top toolbar.
    @Binding var isEraser: Bool
    @Binding var penColor: Color
    @Binding var penWidth: Double

    // Callbacks.
    var onCircleDetected: (InkSelection) -> Void = { _ in }
    var onLongPressProblem: (InkSelection) -> Void = { _ in }
    var onWritingChanged: (Bool) -> Void = { _ in }
    var onOrdinaryStroke: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .pencilOnly            // finger = scroll/gestures
        canvas.alwaysBounceVertical = true
        canvas.showsVerticalScrollIndicator = true
        canvas.backgroundColor = PaperTheme.uiColor(fromHex: paperColorHex)

        // Grid behind the ink.
        let grid = GridBackgroundView()
        canvas.addSubview(grid)
        canvas.sendSubviewToBack(grid)
        context.coordinator.gridView = grid

        if let drawing = try? PKDrawing(data: page.drawingData) {
            canvas.drawing = drawing
        }
        context.coordinator.canvas = canvas

        // Long-press (finger) selects a problem.
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        canvas.addGestureRecognizer(longPress)

        context.coordinator.applyAppearance()
        context.coordinator.applyTool()
        DispatchQueue.main.async { context.coordinator.growContentIfNeeded(minimumHeight: 2400) }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyAppearance()
        context.coordinator.applyTool()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        weak var canvas: PKCanvasView?
        weak var gridView: GridBackgroundView?

        private var hasLoaded = false
        private var isEditingProgrammatically = false

        init(_ parent: PencilCanvasView) { self.parent = parent }

        // MARK: Appearance & tool

        func applyAppearance() {
            guard let canvas else { return }
            canvas.backgroundColor = PaperTheme.uiColor(fromHex: parent.paperColorHex)
            gridView?.configure(
                spacing: CGFloat(parent.gridSpacing),
                paper: PaperTheme.uiColor(fromHex: parent.paperColorHex),
                grid: PaperTheme.gridUIColor(forPaperHex: parent.paperColorHex),
                shows: parent.showsGrid)
            syncGridFrame()
        }

        func applyTool() {
            guard let canvas else { return }
            if parent.isEraser {
                canvas.tool = PKEraserTool(.vector)
            } else {
                canvas.tool = PKInkingTool(.pen, color: UIColor(parent.penColor), width: CGFloat(parent.penWidth))
            }
        }

        // MARK: Infinite growth

        func growContentIfNeeded(minimumHeight: CGFloat) {
            guard let canvas else { return }
            let width = canvas.bounds.width
            let neededForDrawing = canvas.drawing.bounds.maxY + 600
            let target = max(minimumHeight, neededForDrawing, canvas.contentSize.height)
            if canvas.contentSize.width != width || canvas.contentSize.height < target {
                canvas.contentSize = CGSize(width: width, height: target)
            }
            syncGridFrame()
        }

        private func syncGridFrame() {
            guard let canvas, let gridView else { return }
            let size = CGSize(width: canvas.bounds.width,
                              height: max(canvas.contentSize.height, canvas.bounds.height))
            if gridView.frame.size != size {
                gridView.frame = CGRect(origin: .zero, size: size)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let canvas else { return }
            // Extend downward as the user nears the bottom.
            if scrollView.contentOffset.y + scrollView.bounds.height > canvas.contentSize.height - 800 {
                growContentIfNeeded(minimumHeight: canvas.contentSize.height + 1600)
            }
        }

        // MARK: Drawing

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            parent.onWritingChanged(true)
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            parent.onWritingChanged(false)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard hasLoaded else { hasLoaded = true; return }
            guard !isEditingProgrammatically else { return }

            let drawing = canvasView.drawing
            if let result = CircleGestureDetector.detect(in: drawing), result.hasEnclosedInk {
                handleCircleGesture(result, on: canvasView, drawing: drawing)
            } else {
                save(drawing)
                parent.onOrdinaryStroke()
            }
            growContentIfNeeded(minimumHeight: canvasView.contentSize.height)
        }

        // MARK: Circle gesture

        private func handleCircleGesture(_ result: CircleGestureResult,
                                         on canvasView: PKCanvasView,
                                         drawing: PKDrawing) {
            let cleaned = CircleGestureDetector.removingLoop(result, from: drawing)
            isEditingProgrammatically = true
            canvasView.drawing = cleaned
            isEditingProgrammatically = false
            save(cleaned)

            let padded = result.contentRect.insetBy(dx: -16, dy: -16)
            let image = DrawingRasterizer.whiteBackedImage(from: cleaned, rect: padded, scale: 3)

            let offset = canvasView.contentOffset
            let loop = result.loopRect
            let viewRect = CGRect(x: loop.minX - offset.x, y: loop.minY - offset.y,
                                  width: loop.width, height: loop.height)
            let anchor = CGPoint(x: viewRect.midX, y: max(viewRect.minY, 8))

            parent.onCircleDetected(InkSelection(anchorInView: anchor,
                                                 highlightRectInView: viewRect,
                                                 croppedImage: image))
        }

        // MARK: Long press

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let canvas else { return }
            let point = gesture.location(in: canvas) // content coordinates

            // Cluster nearby strokes into a selection region.
            var region = CGRect.null
            for stroke in canvas.drawing.strokes {
                let bounds = stroke.renderBounds
                if bounds.insetBy(dx: -24, dy: -24).contains(point) {
                    region = region.union(bounds)
                }
            }
            if region.isNull {
                region = CGRect(x: point.x - 90, y: point.y - 45, width: 180, height: 90)
            }
            let padded = region.insetBy(dx: -16, dy: -16)
            let image = DrawingRasterizer.whiteBackedImage(from: canvas.drawing, rect: padded, scale: 3)

            let offset = canvas.contentOffset
            let viewRect = CGRect(x: padded.minX - offset.x, y: padded.minY - offset.y,
                                  width: padded.width, height: padded.height)
            let anchor = CGPoint(x: viewRect.midX, y: max(viewRect.minY, 8))

            parent.onLongPressProblem(InkSelection(anchorInView: anchor,
                                                   highlightRectInView: viewRect,
                                                   croppedImage: image))
        }

        // MARK: Saving

        private func save(_ drawing: PKDrawing) {
            parent.page.drawingData = drawing.dataRepresentation()
            parent.page.notepad?.markEdited()
        }
    }
}

// MARK: - Grid background

/// Draws the paper fill and grid lines. Added behind the ink so strokes always
/// render on top of the grid.
final class GridBackgroundView: UIView {
    private var spacing: CGFloat = 32
    private var gridColor: UIColor = .gray
    private var shows = true

    func configure(spacing: CGFloat, paper: UIColor, grid: UIColor, shows: Bool) {
        self.spacing = max(spacing, 8)
        self.gridColor = grid
        self.shows = shows
        backgroundColor = paper
        isUserInteractionEnabled = false
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard shows, let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(gridColor.cgColor)
        context.setLineWidth(1.0 / (window?.screen.scale ?? 2))

        var x: CGFloat = 0
        while x <= bounds.width {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: bounds.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= bounds.height {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
            y += spacing
        }
        context.strokePath()
    }
}

// MARK: - Rasterizer

/// Renders a PKDrawing region onto a white background so Vision's text
/// recognizer sees dark ink on a light field.
enum DrawingRasterizer {
    static func whiteBackedImage(from drawing: PKDrawing, rect: CGRect, scale: CGFloat) -> UIImage {
        let safeRect = rect.isNull || rect.isEmpty ? CGRect(x: 0, y: 0, width: 10, height: 10) : rect
        let inkImage = drawing.image(from: safeRect, scale: scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: safeRect.size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: safeRect.size))
            inkImage.draw(in: CGRect(origin: .zero, size: safeRect.size))
        }
    }
}
#endif
