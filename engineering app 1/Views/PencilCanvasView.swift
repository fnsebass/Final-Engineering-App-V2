//
//  PencilCanvasView.swift
//  Tolerance
//
//  The infinite PencilKit canvas with a background paper grid.
//
//  Layout: a container holds a grid view and, on top of it, a TRANSPARENT
//  PKCanvasView. The grid is a viewport-sized backdrop that shifts with the
//  canvas's scroll offset, so it appears continuous/infinite and always sits
//  behind the ink. The grid is never part of the PKDrawing, so it is never
//  saved, exported, or seen by the circle-gesture detector.
//
//  Input policy: `pencilOnly` off (default) → any input draws (finger, mouse,
//  Pencil). On → only an Apple Pencil draws.
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

    let paperColorHex: String
    let paperStyle: PaperStyle
    let gridColumns: Int

    @Binding var isEraser: Bool
    @Binding var penColor: Color
    @Binding var penWidth: Double
    @Binding var pencilOnly: Bool

    var onCircleDetected: (InkSelection) -> Void = { _ in }
    var onLongPressProblem: (InkSelection) -> Void = { _ in }
    var onWritingChanged: (Bool) -> Void = { _ in }
    var onOrdinaryStroke: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> CanvasContainerView {
        let container = CanvasContainerView()
        let canvas = container.canvas
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.alwaysBounceVertical = true

        if let drawing = try? PKDrawing(data: page.drawingData) {
            canvas.drawing = drawing
        }
        context.coordinator.container = container

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        canvas.addGestureRecognizer(longPress)

        context.coordinator.applyAppearance()
        context.coordinator.applyTool()
        context.coordinator.growContentIfNeeded(minimumHeight: 2400)
        return container
    }

    func updateUIView(_ container: CanvasContainerView, context: Context) {
        context.coordinator.parent = self
        let desiredPolicy: PKCanvasViewDrawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        if container.canvas.drawingPolicy != desiredPolicy {
            container.canvas.drawingPolicy = desiredPolicy
        }
        context.coordinator.applyAppearance()
        context.coordinator.applyTool()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        weak var container: CanvasContainerView?

        private var hasLoaded = false
        private var isEditingProgrammatically = false

        init(_ parent: PencilCanvasView) { self.parent = parent }

        private var canvas: PKCanvasView? { container?.canvas }

        // MARK: Appearance & tool

        func applyAppearance() {
            guard let container else { return }
            let paper = PaperTheme.uiColor(fromHex: parent.paperColorHex)
            container.backgroundColor = paper
            container.canvas.backgroundColor = .clear
            container.canvas.isOpaque = false
            container.grid.configure(style: parent.paperStyle, columns: parent.gridColumns, paper: paper)
            container.grid.scrollOffsetY = container.canvas.contentOffset.y
            container.grid.setNeedsDisplay()
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
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            container?.grid.scrollOffsetY = scrollView.contentOffset.y
            container?.grid.setNeedsDisplay()
            if let canvas,
               scrollView.contentOffset.y + scrollView.bounds.height > canvas.contentSize.height - 800 {
                growContentIfNeeded(minimumHeight: canvas.contentSize.height + 1600)
            }
        }

        // MARK: Drawing

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { parent.onWritingChanged(true) }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { parent.onWritingChanged(false) }

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

        private func save(_ drawing: PKDrawing) {
            parent.page.drawingData = drawing.dataRepresentation()
            parent.page.notepad?.markEdited()
        }
    }
}

// MARK: - Container

/// Holds the grid backdrop and a transparent PKCanvasView on top of it.
final class CanvasContainerView: UIView {
    let grid = GridBackgroundView()
    let canvas = PKCanvasView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(grid)
        addSubview(canvas)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        grid.frame = bounds
        canvas.frame = bounds
    }
}

// MARK: - Paper background

/// Draws the paper fill and the selected paper style (grid / dots / lined) as a
/// viewport-sized backdrop that shifts with the canvas scroll offset. The
/// line/dot color is a de-emphasized light gray.
final class GridBackgroundView: UIView {
    private var style: PaperStyle = .blank
    private var columns: Int = 16
    var scrollOffsetY: CGFloat = 0

    private let lineColor = UIColor(red: 0xD0 / 255.0, green: 0xD0 / 255.0, blue: 0xD0 / 255.0, alpha: 1.0)

    func configure(style: PaperStyle, columns: Int, paper: UIColor) {
        self.style = style
        self.columns = max(columns, 2)
        backgroundColor = paper
        isUserInteractionEnabled = false
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard style != .blank, bounds.width > 0, let context = UIGraphicsGetCurrentContext() else { return }

        let spacing = bounds.width / CGFloat(columns)
        guard spacing >= 3 else { return }

        // Vertical alignment shifts with scroll so the grid looks continuous.
        let phase = scrollOffsetY.truncatingRemainder(dividingBy: spacing)
        let firstY = -phase

        switch style {
        case .blank:
            break

        case .grid:
            context.setStrokeColor(lineColor.cgColor)
            context.setLineWidth(0.5) // hairline
            var x: CGFloat = 0
            while x <= bounds.width + 0.5 {
                context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: bounds.height)); x += spacing
            }
            var y = firstY
            while y <= bounds.height + 0.5 {
                context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: bounds.width, y: y)); y += spacing
            }
            context.strokePath()

        case .dots:
            context.setFillColor(lineColor.cgColor)
            let diameter: CGFloat = 1.8
            var y = firstY
            while y <= bounds.height + spacing {
                var x: CGFloat = 0
                while x <= bounds.width + 0.5 {
                    context.fillEllipse(in: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter))
                    x += spacing
                }
                y += spacing
            }

        case .lined:
            context.setStrokeColor(lineColor.cgColor)
            context.setLineWidth(0.5)
            var y = firstY
            while y <= bounds.height + 0.5 {
                context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: bounds.width, y: y)); y += spacing
            }
            context.strokePath()
        }
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
