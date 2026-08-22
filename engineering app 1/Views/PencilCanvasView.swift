//
//  PencilCanvasView.swift
//  Tolerance
//
//  Grid fix: PKCanvasView's private drawing layers sit on top of any subview
//  inserted into the canvas, making the old "insertSubview(grid, at: 0)"
//  approach invisible. The fix uses a CanvasWrapper UIView that holds:
//    • GridContentView      (z = 0) — draws paper lines / grid / dots
//    • CanvasView           (z = 1) — PKCanvasView with backgroundColor = .clear
//    • StraightLineOverlay  (z = 2) — intercepts pencil touches for live line preview
//  Because the canvas is transparent where there is no ink, the grid shows
//  through correctly. The grid redraws itself using a scrollOffset property
//  that the coordinator keeps in sync with the canvas's contentOffset.
//
//  Straight-line tool:
//    When active the StraightLineOverlay intercepts all pencil touches via
//    hitTest. It shows a live CAShapeLayer preview from start to current
//    position. On pencil-up it commits a PKStroke built from evenly-spaced
//    control points, giving a clean uniform straight line in PencilKit.
//
//  Apple Pencil interactions:
//    • Squeeze (Pencil Pro)  → hold to activate eraser, release to restore tool
//    • Double-tap (Pencil 2) → toggle eraser on/off
//

#if os(iOS)
import SwiftUI
import PencilKit

struct PencilCanvasView: UIViewRepresentable {
    let page: Page
    let paperColorHex: String
    let paperStyle: PaperStyle
    let gridColumns: Int
    @Binding var activeTool: DrawingTool
    @Binding var penColor: Color
    let penWidth: Double

    /// True when the paper background is dark (luminance < 0.5).
    private var isDarkPaper: Bool {
        let hex = paperColorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let v = UInt64(hex, radix: 16) else { return false }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >>  8) & 0xFF) / 255
        let b = Double(v         & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.5
    }

    var onLongPressPreview: (CGPoint) -> Void = { _ in }
    var onLongPressPreviewEnd: () -> Void = {}
    var onLongPress: (CGPoint, UIImage) -> Void = { _, _ in }
    var onPencilSqueezeBegan: () -> Void = {}
    var onPencilSqueezeEnded: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(page: page) }

    /// Converts a SwiftUI Color to a fixed (non-adaptive) UIColor for PKInkingTool.
    /// PKCanvasView in dark mode inverts dynamic colors, so we resolve to explicit sRGB
    /// values using a light-mode trait collection, matching the canvas's forced style.
    private func inkUIColor(from color: Color) -> UIColor {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
           .getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    func makeUIView(context: Context) -> CanvasWrapper {
        let paper   = PaperTheme.uiColor(fromHex: paperColorHex)
        let wrapper = CanvasWrapper()
        let canvas  = wrapper.canvas
        let grid    = wrapper.gridView

        // Force light-mode so PKCanvasView never inverts stroke colors.
        wrapper.overrideUserInterfaceStyle = .light

        grid.setup(style: paperStyle, columns: gridColumns, paper: paper)

        canvas.backgroundColor = .clear
        canvas.isOpaque        = false
        canvas.drawingPolicy   = .pencilOnly
        canvas.isScrollEnabled = true
        canvas.alwaysBounceVertical = true
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.tool = PKInkingTool(.pen, color: inkUIColor(from: penColor), width: CGFloat(penWidth))

        if let drawing = try? PKDrawing(data: page.drawingData) {
            canvas.drawing = drawing
        }

        canvas.delegate = context.coordinator
        context.coordinator.canvas             = canvas
        context.coordinator.gridView           = grid
        context.coordinator.straightLineOverlay = wrapper.straightLineOverlay
        context.coordinator.onPencilSqueezeBegan = onPencilSqueezeBegan
        context.coordinator.onPencilSqueezeEnded = onPencilSqueezeEnded

        // Wire straight-line overlay commit callback
        let coord = context.coordinator
        wrapper.straightLineOverlay.onCommit = { [weak coord] start, end in
            coord?.commitLine(from: start, to: end)
        }

        // 0.2 s: preview ring
        let earlyPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleEarlyPress(_:))
        )
        earlyPress.minimumPressDuration = 0.2
        earlyPress.allowableMovement = 8
        earlyPress.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        earlyPress.cancelsTouchesInView = false
        earlyPress.delaysTouchesBegan   = false
        earlyPress.delegate = context.coordinator
        canvas.addGestureRecognizer(earlyPress)

        // 0.4 s: context menu + OCR capture
        let fullPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        fullPress.minimumPressDuration = 0.4
        fullPress.allowableMovement = 8
        fullPress.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        fullPress.cancelsTouchesInView = false
        fullPress.delaysTouchesBegan   = false
        fullPress.delegate = context.coordinator
        canvas.addGestureRecognizer(fullPress)

        context.coordinator.isDarkPaper           = isDarkPaper
        context.coordinator.onLongPressPreview    = onLongPressPreview
        context.coordinator.onLongPressPreviewEnd = onLongPressPreviewEnd
        context.coordinator.onLongPress           = onLongPress

        // Apple Pencil interaction (double-tap + Pencil Pro squeeze)
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvas.addInteraction(pencilInteraction)

        return wrapper
    }

    func updateUIView(_ wrapper: CanvasWrapper, context: Context) {
        let canvas = wrapper.canvas
        let coord  = context.coordinator
        let overlay = wrapper.straightLineOverlay

        coord.isDarkPaper           = isDarkPaper
        coord.onLongPressPreview    = onLongPressPreview
        coord.onLongPressPreviewEnd = onLongPressPreviewEnd
        coord.onLongPress           = onLongPress
        coord.onPencilSqueezeBegan  = onPencilSqueezeBegan
        coord.onPencilSqueezeEnded  = onPencilSqueezeEnded

        let paper = PaperTheme.uiColor(fromHex: paperColorHex)
        wrapper.gridView.setup(style: paperStyle, columns: gridColumns, paper: paper)

        // Store current ink properties so the coordinator can commit straight lines.
        let inkColor = inkUIColor(from: penColor)
        coord.currentInkColor = inkColor
        coord.currentPenWidth = CGFloat(penWidth)

        // Apply tool to PKCanvasView (used for all non-straight-line tools and
        // for the long-press OCR ink reference).
        coord.activeTool = activeTool
        applyTool(to: canvas, tool: activeTool, color: inkColor, width: CGFloat(penWidth))

        // Activate or deactivate the straight-line overlay.
        overlay.inkColor     = inkColor
        overlay.inkWidth     = CGFloat(penWidth)
        overlay.scrollOffset = canvas.contentOffset.y
        if activeTool == .straightLine {
            overlay.activate()
        } else {
            overlay.deactivate()
        }
    }

    private func applyTool(to canvas: CanvasView, tool: DrawingTool, color: UIColor, width: CGFloat) {
        switch tool {
        case .pen, .straightLine: canvas.tool = PKInkingTool(.pen,    color: color, width: width)
        case .marker:             canvas.tool = PKInkingTool(.marker, color: color, width: width * 4)
        case .eraser:             canvas.tool = PKEraserTool(.vector)
        case .lasso:              canvas.tool = PKLassoTool()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate,
                             UIPencilInteractionDelegate {
        let page: Page
        weak var canvas: CanvasView?
        weak var gridView: GridContentView?
        weak var straightLineOverlay: StraightLineOverlay?

        var activeTool: DrawingTool = .pen
        var isDrawing  = false
        private var isResettingCanvas = false

        // Ink state used when building a straight-line PKStroke.
        var currentInkColor: UIColor = .black
        var currentPenWidth: CGFloat = 3

        // The PKTool that was on the canvas before squeeze/double-tap activated
        // the eraser. Stored here so we can restore it directly on the canvas the
        // instant the squeeze releases, without waiting for SwiftUI's update cycle.
        var toolBeforeSqueeze: PKTool? = nil

        var isDarkPaper = false

        var onLongPressPreview: (CGPoint) -> Void = { _ in }
        var onLongPressPreviewEnd: () -> Void = {}
        var onLongPress: (CGPoint, UIImage) -> Void = { _, _ in }
        var onPencilSqueezeBegan: () -> Void = {}
        var onPencilSqueezeEnded: () -> Void = {}

        init(page: Page) { self.page = page }

        // Gesture recognizer delegate — both long-press recognizers fire simultaneously.
        func gestureRecognizer(_ gr: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ gr: UIGestureRecognizer,
                               shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }

        // MARK: Long press

        @objc func handleEarlyPress(_ gesture: UILongPressGestureRecognizer) {
            guard let canvas = canvas else { return }
            switch gesture.state {
            case .began:
                onLongPressPreview(viewPos(for: gesture, in: canvas))
            case .ended, .cancelled, .failed:
                onLongPressPreviewEnd()
            default: break
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let canvas = canvas else { return }
            let contentPos = gesture.location(in: canvas)
            onLongPress(viewPos(for: gesture, in: canvas),
                        captureOCRImage(from: canvas.drawing, around: contentPos))
        }

        private func viewPos(for gesture: UILongPressGestureRecognizer, in canvas: CanvasView) -> CGPoint {
            let p = gesture.location(in: canvas)
            return CGPoint(x: p.x, y: p.y - canvas.contentOffset.y)
        }

        private func captureOCRImage(from drawing: PKDrawing, around center: CGPoint) -> UIImage {
            let region = CGRect(x: center.x - 400, y: center.y - 220, width: 800, height: 440)

            // On a dark paper the ink is light-colored. Render it in its native style
            // (no trait-collection override) so we preserve the actual ink color,
            // then composite on a BLACK background so OCR sees dark text on light bg
            // after we invert. For light paper, the standard white-background path works.
            var inkImage = UIImage()
            if isDarkPaper {
                inkImage = drawing.image(from: region, scale: 2)
            } else {
                UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                    inkImage = drawing.image(from: region, scale: 2)
                }
            }

            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let composed = UIGraphicsImageRenderer(size: region.size, format: format).image { ctx in
                let bg: UIColor = isDarkPaper ? .black : .white
                bg.setFill()
                ctx.fill(CGRect(origin: .zero, size: region.size))
                inkImage.draw(in: CGRect(origin: .zero, size: region.size))
            }

            // If dark paper: invert the image so OCR sees black ink on white background
            guard isDarkPaper else { return composed }
            guard let cgImg = composed.cgImage,
                  let filter = CIFilter(name: "CIColorInvert") else { return composed }
            filter.setValue(CIImage(cgImage: cgImg), forKey: kCIInputImageKey)
            let ctx = CIContext()
            guard let output = filter.outputImage,
                  let inverted = ctx.createCGImage(output, from: output.extent) else { return composed }
            return UIImage(cgImage: inverted)
        }

        // MARK: Straight-line stroke commit

        /// Called by StraightLineOverlay when the pencil lifts.
        /// `start` and `end` are in PKCanvasView content coordinates.
        func commitLine(from start: CGPoint, to end: CGPoint) {
            guard let canvas = canvas else { return }
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > 2 else { return }   // ignore accidental taps

            // One control point every ~10 pts produces a smooth, correctly-tapered stroke.
            let numPts = max(3, Int(length / 10) + 2)
            var pts: [PKStrokePoint] = []
            for i in 0..<numPts {
                let t = Double(i) / Double(numPts - 1)
                pts.append(PKStrokePoint(
                    location: CGPoint(
                        x: start.x + (end.x - start.x) * t,
                        y: start.y + (end.y - start.y) * t
                    ),
                    timeOffset: t,
                    size: CGSize(width: currentPenWidth, height: currentPenWidth),
                    opacity: 1.0,
                    force: 1.0,
                    azimuth: 0,
                    altitude: .pi / 2   // pencil perpendicular → uniform width
                ))
            }

            let path   = PKStrokePath(controlPoints: pts, creationDate: Date())
            let ink    = PKInk(.pen, color: currentInkColor)
            let stroke = PKStroke(ink: ink, path: path)
            var drawing = canvas.drawing
            drawing.strokes.append(stroke)
            canvas.drawing = drawing
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { isDrawing = true }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { isDrawing = false }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            gridView?.scrollOffset = scrollView.contentOffset.y
            gridView?.setNeedsDisplay()
            straightLineOverlay?.scrollOffset = scrollView.contentOffset.y

            guard let canvas = canvas,
                  scrollView.bounds.height > 0,
                  scrollView.contentOffset.y + scrollView.bounds.height
                    > scrollView.contentSize.height - 800 else { return }
            grow(canvas, by: 1600)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Guard against the recursive call that occurs when we programmatically
            // assign a fresh PKDrawing() below to wake up the canvas.
            guard !isResettingCanvas else { return }
            page.drawingData = canvasView.drawing.dataRepresentation()
            page.notepad?.markEdited()
            if let canvas = canvas {
                let needed = canvas.drawing.bounds.maxY + 600
                if canvas.contentSize.height < needed { grow(canvas, to: needed + 1600) }

                // PKCanvasView enters a zombie state when the last stroke is erased.
                // Assigning a fresh PKDrawing() wakes it up, but doing so synchronously
                // inside this callback triggers PencilKit's "Drawing count mismatch" warning
                // because PencilKit's own stroke-count update hasn't finished yet.
                // Deferring one run loop cycle lets PencilKit settle before we reassign.
                // The flag prevents the deferred assignment from re-entering this block.
                if canvasView.drawing.strokes.isEmpty {
                    isResettingCanvas = true
                    DispatchQueue.main.async { [weak self, weak canvasView] in
                        if let cv = canvasView { cv.drawing = PKDrawing() }
                        self?.isResettingCanvas = false
                    }
                }
            }
        }

        private func grow(_ c: CanvasView, by delta: CGFloat) { grow(c, to: c.contentSize.height + delta) }
        private func grow(_ c: CanvasView, to height: CGFloat) {
            guard c.bounds.width > 0 else { return }
            c.contentSize = CGSize(width: c.bounds.width, height: height)
        }

        // MARK: UIPencilInteractionDelegate

        // Apple Pencil 2 double-tap → toggle eraser on / off.
        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            if activeTool == .eraser {
                if let saved = toolBeforeSqueeze { canvas?.tool = saved }
                toolBeforeSqueeze = nil
                onPencilSqueezeEnded()
            } else {
                toolBeforeSqueeze = canvas?.tool
                canvas?.tool = PKEraserTool(.vector)
                onPencilSqueezeBegan()
            }
        }

        // Apple Pencil Pro squeeze → hold-to-erase.
        func pencilInteraction(_ interaction: UIPencilInteraction,
                               didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            switch squeeze.phase {
            case .began:
                toolBeforeSqueeze = canvas?.tool
                canvas?.tool = PKEraserTool(.vector)
                onPencilSqueezeBegan()
            case .ended, .cancelled:
                if let saved = toolBeforeSqueeze { canvas?.tool = saved }
                toolBeforeSqueeze = nil
                onPencilSqueezeEnded()
            default: break
            }
        }
    }
}

// MARK: - CanvasWrapper

/// Container: GridContentView (z=0) → CanvasView (z=1) → StraightLineOverlay (z=2).
final class CanvasWrapper: UIView {
    let canvas: CanvasView
    let gridView: GridContentView
    let straightLineOverlay: StraightLineOverlay

    init() {
        canvas              = CanvasView()
        gridView            = GridContentView()
        straightLineOverlay = StraightLineOverlay()
        super.init(frame: .zero)
        addSubview(gridView)             // z = 0
        addSubview(canvas)               // z = 1
        addSubview(straightLineOverlay)  // z = 2, intercepts pencil touches when active
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame              = bounds
        gridView.frame            = bounds
        straightLineOverlay.frame = bounds
    }
}

// MARK: - StraightLineOverlay

/// Transparent view that sits above the canvas when the straight-line tool is active.
/// It intercepts pencil touches via hitTest, draws a live CAShapeLayer preview, and
/// calls onCommit(start, end) with content-space coordinates when the pencil lifts.
/// Finger touches fall through so two-finger scrolling still works.
final class StraightLineOverlay: UIView {
    var onCommit: ((CGPoint, CGPoint) -> Void)?

    /// Ink color for the live preview line (should match the active pen color).
    var inkColor: UIColor = .black { didSet { lineLayer.strokeColor = inkColor.cgColor } }
    /// Stroke width for the preview (should match the active pen width).
    var inkWidth: CGFloat = 3     { didSet { lineLayer.lineWidth = inkWidth } }
    /// PKCanvasView's current contentOffset.y — used to convert view → content coordinates.
    var scrollOffset: CGFloat = 0

    private(set) var isCapturing = false
    private var startPoint: CGPoint?
    private let lineLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        lineLayer.fillColor   = UIColor.clear.cgColor
        lineLayer.lineCap     = .round
        lineLayer.lineJoin    = .round
        layer.addSublayer(lineLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    func activate() {
        lineLayer.strokeColor = inkColor.cgColor
        lineLayer.lineWidth   = inkWidth
        isCapturing = true
        isUserInteractionEnabled = true
    }

    func deactivate() {
        isCapturing = false
        isUserInteractionEnabled = false
        clearPreview()
        startPoint = nil
    }

    // Only intercept pencil touches — return nil for everything else so finger
    // touches fall through to the canvas for scrolling.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isCapturing, bounds.contains(point) else { return nil }
        // Check if the initiating touch is a pencil; pass finger touches through.
        if let touch = event?.allTouches?.first, touch.type != .pencil { return nil }
        return self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first(where: { $0.type == .pencil }) else { return }
        let pt = t.location(in: self)
        startPoint = pt
        updatePreview(from: pt, to: pt)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first(where: { $0.type == .pencil }),
              let start = startPoint else { return }
        updatePreview(from: start, to: t.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first(where: { $0.type == .pencil }),
              let start = startPoint else {
            clearPreview(); startPoint = nil; return
        }
        let end = t.location(in: self)
        clearPreview()
        startPoint = nil
        onCommit?(toContent(start), toContent(end))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        clearPreview()
        startPoint = nil
    }

    private func updatePreview(from start: CGPoint, to current: CGPoint) {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: current)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer.path = path
        CATransaction.commit()
    }

    private func clearPreview() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer.path = nil
        CATransaction.commit()
    }

    /// Convert overlay view-space point to PKCanvasView content-space point.
    private func toContent(_ vp: CGPoint) -> CGPoint {
        CGPoint(x: vp.x, y: vp.y + scrollOffset)
    }
}

// MARK: - CanvasView (PKCanvasView subclass)

final class CanvasView: PKCanvasView {
    // Suppress the built-in selection edit menu (cut, copy, delete, duplicate,
    // insert space above) so only our custom long-press pill menu is shown.
    override func addInteraction(_ interaction: UIInteraction) {
        if interaction is UIContextMenuInteraction { return }
        super.addInteraction(interaction)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
    override func target(forAction action: Selector, withSender sender: Any?) -> Any? { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if contentSize.width < bounds.width || contentSize.height < bounds.height {
            contentSize = CGSize(width: bounds.width,
                                 height: max(contentSize.height, 8000))
        }
    }
}

// MARK: - GridContentView

/// Draws paper grid lines / ruled lines / dot grid for the visible viewport.
/// scrollOffset mirrors the canvas's contentOffset.y so lines appear fixed
/// relative to the paper even as the user scrolls.
final class GridContentView: UIView {
    private(set) var currentStyle: PaperStyle = .blank
    private(set) var currentColumns: Int = 16
    private var lineColor: UIColor = UIColor(red: 0.0, green: 0.47, blue: 0.84, alpha: 0.4)

    var scrollOffset: CGFloat = 0

    func setup(style: PaperStyle, columns: Int, paper: UIColor) {
        currentStyle   = style
        currentColumns = max(columns, 2)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        paper.getRed(&r, green: &g, blue: &b, alpha: nil)
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        lineColor = lum > 0.45
            ? UIColor(red: 0.0, green: 0.47, blue: 0.84, alpha: 0.4)
            : UIColor(white: 0.85, alpha: 0.4)

        backgroundColor          = paper
        isUserInteractionEnabled = false
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard currentStyle != .blank, bounds.width > 0,
              let ctx = UIGraphicsGetCurrentContext() else { return }

        let spacing = bounds.width / CGFloat(currentColumns)
        guard spacing >= 3 else { return }

        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setFillColor(lineColor.cgColor)
        ctx.setLineWidth(0.5)

        let kMin   = Int(ceil((rect.minY + scrollOffset) / spacing))
        let firstY = CGFloat(max(kMin, 0)) * spacing - scrollOffset

        switch currentStyle {
        case .blank:
            break

        case .grid:
            var x: CGFloat = 0
            while x <= bounds.width + 0.5 {
                ctx.move(to: CGPoint(x: x, y: rect.minY))
                ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += spacing
            }
            var y = firstY
            while y <= rect.maxY + 0.5 {
                ctx.move(to: CGPoint(x: 0,            y: y))
                ctx.addLine(to: CGPoint(x: bounds.width, y: y))
                y += spacing
            }
            ctx.strokePath()

        case .lined:
            var y = firstY
            while y <= rect.maxY + 0.5 {
                ctx.move(to: CGPoint(x: 0,            y: y))
                ctx.addLine(to: CGPoint(x: bounds.width, y: y))
                y += spacing
            }
            ctx.strokePath()

        case .dots:
            let d: CGFloat = 1.8
            var y = firstY
            while y <= rect.maxY + spacing {
                var x: CGFloat = 0
                while x <= bounds.width + 0.5 {
                    ctx.fillEllipse(in: CGRect(x: x - d/2, y: y - d/2, width: d, height: d))
                    x += spacing
                }
                y += spacing
            }
        }
    }
}
#endif
