//
//  PencilCanvasView.swift
//  Tolerance
//
//  The infinite, grid-lined PencilKit canvas.
//
//  Input policy: finger/mouse can draw by default. As soon as an Apple Pencil
//  is used, the canvas switches to Pencil-only (so a resting hand/finger won't
//  mark the page). If no Pencil is ever used, any input keeps working.
//
//  Grid: drawn by a background subview owned by a PKCanvasView subclass, laid
//  out to cover the whole scrollable content and always kept behind the ink.
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

    func makeUIView(context: Context) -> GriddedCanvasView {
        let canvas = GriddedCanvasView()
        canvas.delegate = context.coordinator
        // Start permissive so finger/mouse works; the Pencil detector below
        // flips this to Pencil-only the first time a Pencil is used.
        canvas.drawingPolicy = .anyInput
        canvas.alwaysBounceVertical = true
        canvas.showsVerticalScrollIndicator = true

        if let drawing = try? PKDrawing(data: page.drawingData) {
            canvas.drawing = drawing
        }
        context.coordinator.canvas = canvas

        // Long-press (finger) selects a problem for the pill menu.
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        canvas.addGestureRecognizer(longPress)

        // Detects Apple Pencil touches (without consuming them) to switch modes.
        let pencilDetector = PencilDetectorGesture()
        pencilDetector.onPencil = { [weak canvas] in
            if canvas?.drawingPolicy != .pencilOnly { canvas?.drawingPolicy = .pencilOnly }
        }
        canvas.addGestureRecognizer(pencilDetector)

        context.coordinator.applyAppearance()
        context.coordinator.applyTool()
        context.coordinator.growContentIfNeeded(minimumHeight: 2400)
        return canvas
    }

    func updateUIView(_ canvas: GriddedCanvasView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyAppearance()
        context.coordinator.applyTool()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        weak var canvas: GriddedCanvasView?

        private var hasLoaded = false
        private var isEditingProgrammatically = false

        init(_ parent: PencilCanvasView) { self.parent = parent }

        // MARK: Appearance & tool

        func applyAppearance() {
            guard let canvas else { return }
            canvas.backgroundColor = PaperTheme.uiColor(fromHex: parent.paperColorHex)
            canvas.grid.configure(
                spacing: CGFloat(parent.gridSpacing),
                paper: PaperTheme.uiColor(fromHex: parent.paperColorHex),
                grid: PaperTheme.gridUIColor(forPaperHex: parent.paperColorHex),
                shows: parent.showsGrid)
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
            let width = max(canvas.bounds.width, 1)
            let neededForDrawing = canvas.drawing.bounds.maxY + 600
            let target = max(minimumHeight, neededForDrawing, canvas.contentSize.height)
            if abs(canvas.contentSize.width - width) > 0.5 || canvas.contentSize.height < target {
                canvas.contentSize = CGSize(width: width, height: target)
                canvas.setNeedsLayout()
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let canvas else { return }
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
            let point = gesture.location(in: canvas)

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

// MARK: - Gridded canvas subclass

/// A PKCanvasView that owns a grid background and keeps it sized to the full
/// scrollable content and behind the ink.
final class GriddedCanvasView: PKCanvasView {
    let grid = GridBackgroundView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(grid)
        sendSubviewToBack(grid)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = max(contentSize.height, bounds.height)
        let size = CGSize(width: width, height: height)
        if grid.frame.size != size {
            grid.frame = CGRect(origin: .zero, size: size)
        }
        sendSubviewToBack(grid)
    }
}

// MARK: - Grid background

/// Draws the paper fill and grid lines.
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
        context.setLineWidth(max(1.0 / (window?.screen.scale ?? 2), 0.5))

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

// MARK: - Pencil detection

/// A do-nothing gesture recognizer that reports when an Apple Pencil touch is
/// seen, then fails immediately so it never interferes with drawing/scrolling.
final class PencilDetectorGesture: UIGestureRecognizer {
    var onPencil: () -> Void = {}

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if touches.contains(where: { $0.type == .pencil }) { onPencil() }
        state = .failed
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
