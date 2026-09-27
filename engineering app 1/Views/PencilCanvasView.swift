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
//  Apple Pencil interactions (UIPencilInteractionDelegate — hardware events,
//  unrelated to the finger double-tap gesture recognizer below):
//    • Squeeze (Pencil Pro)  → opens the curved RadialToolMenu palette by default
//    • Double-tap (Pencil 2) → toggle eraser on/off
//    (Both configurable in Settings → Writing → Pen Buttons.)
//
//  Finger double-tap on the canvas opens the quick-action menu
//  (Graph/Chemistry/AI Help), handled entirely separately via a
//  UITapGestureRecognizer restricted to `.direct` (finger) touches.
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
    let activeShapeKind: ShapeKind

    /// True when the paper background is dark (luminance < 0.5).
    private var isDarkPaper: Bool {
        let hex = paperColorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let v = UInt64(hex, radix: 16) else { return false }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >>  8) & 0xFF) / 255
        let b = Double(v         & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.5
    }

    var onDoubleTapMenu: (CGPoint, UIImage) -> Void = { _, _ in }
    /// Called ~1s after the user stops drawing, with a capture of the region
    /// around their most recent stroke, so CanvasWorkspace can automatically
    /// check it and show a check/X badge.
    var onLiveCheckRegion: (CGPoint, UIImage) -> Void = { _, _ in }
    var onPencilSqueezeBegan: () -> Void = {}
    var onPencilSqueezeEnded: () -> Void = {}
    var onRequestTool: (DrawingTool) -> Void = { _ in }
    var onSwitchColor: () -> Void = {}
    /// Settings → Pen Buttons: fired when squeeze (default) or double-tap is
    /// mapped to "Show Tool Palette" — opens RadialToolMenu at the pencil's
    /// current (or last known) position, in canvas view-space coordinates.
    var onShowToolPalette: (CGPoint) -> Void = { _ in }
    var onUndoManagerReady: (UndoManager?) -> Void = { _ in }
    /// Called when the canvas needs to be torn down and rebuilt from scratch
    /// (see the "zombie canvas" comment in `canvasViewDrawingDidChange`). The
    /// caller should respond by changing this view's `.id()`.
    var onNeedsRecreate: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(page: page) }

    /// Settings → Gestures & Touch: "Finger Touch Does" + "Ignore Touch Input
    /// While Pencil Is Active" map directly onto PKCanvasView's own
    /// drawingPolicy — .pencilOnly (finger only pans), .anyInput (finger can
    /// always draw), or .default (finger can draw until Pencil is used, then
    /// locks to Pencil — exactly the "touch lockout" behavior).
    static func resolvedDrawingPolicy() -> PKCanvasViewDrawingPolicy {
        let fingerAction = UserDefaults.standard.string(forKey: "settings.gestures.fingerAction")
            ?? FingerAction.pan.rawValue
        guard fingerAction == FingerAction.draw.rawValue else { return .pencilOnly }
        let lockout = (UserDefaults.standard.object(forKey: "settings.gestures.touchLockout") as? Bool) ?? true
        return lockout ? .default : .anyInput
    }

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
        canvas.drawingPolicy   = Self.resolvedDrawingPolicy()
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

        // Finger double-tap → quick-action menu (Graph/Chemistry/AI Help) + OCR capture.
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        doubleTap.delegate = context.coordinator
        canvas.addGestureRecognizer(doubleTap)

        // Settings → Writing → Gestures & Touch: two-finger undo / three-finger redo.
        // Recognizers are always installed; the coordinator checks the toggle
        // before acting so it stays live-updatable without recreating the view.
        let twoFingerUndo = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTwoFingerUndo(_:))
        )
        twoFingerUndo.numberOfTouchesRequired = 2
        twoFingerUndo.cancelsTouchesInView = false
        twoFingerUndo.delegate = context.coordinator
        canvas.addGestureRecognizer(twoFingerUndo)

        let threeFingerRedo = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleThreeFingerRedo(_:))
        )
        threeFingerRedo.numberOfTouchesRequired = 3
        threeFingerRedo.cancelsTouchesInView = false
        threeFingerRedo.delegate = context.coordinator
        canvas.addGestureRecognizer(threeFingerRedo)

        context.coordinator.isDarkPaper           = isDarkPaper
        context.coordinator.onDoubleTapMenu       = onDoubleTapMenu
        context.coordinator.onLiveCheckRegion     = onLiveCheckRegion
        context.coordinator.onRequestTool         = onRequestTool
        context.coordinator.onSwitchColor         = onSwitchColor
        context.coordinator.onShowToolPalette     = onShowToolPalette
        context.coordinator.onNeedsRecreate       = onNeedsRecreate

        // Wire shape overlay commit callback — reads current shapeKind from overlay at commit time.
        context.coordinator.shapeOverlay = wrapper.shapeOverlay
        wrapper.shapeOverlay.onCommit = { [weak coord] start, end in
            coord?.commitShape(from: start, to: end)
        }

        // Apple Pencil interaction (double-tap + Pencil Pro squeeze)
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvas.addInteraction(pencilInteraction)

        // Tracks where the Pencil currently is (while hovering, on supported
        // hardware) so the tool palette can appear right where it's being
        // held rather than at a fixed toolbar position.
        let hover = UIHoverGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleHover(_:))
        )
        canvas.addGestureRecognizer(hover)

        onUndoManagerReady(canvas.undoManager)

        return wrapper
    }

    func updateUIView(_ wrapper: CanvasWrapper, context: Context) {
        let canvas = wrapper.canvas
        let coord       = context.coordinator
        let overlay     = wrapper.straightLineOverlay
        let shapeOvr    = wrapper.shapeOverlay

        coord.isDarkPaper           = isDarkPaper
        coord.onDoubleTapMenu       = onDoubleTapMenu
        coord.onLiveCheckRegion     = onLiveCheckRegion
        coord.onPencilSqueezeBegan  = onPencilSqueezeBegan
        coord.onPencilSqueezeEnded  = onPencilSqueezeEnded
        coord.onRequestTool        = onRequestTool
        coord.onSwitchColor        = onSwitchColor
        coord.onShowToolPalette    = onShowToolPalette
        coord.onNeedsRecreate      = onNeedsRecreate
        canvas.drawingPolicy       = Self.resolvedDrawingPolicy()

        let paper = PaperTheme.uiColor(fromHex: paperColorHex)
        wrapper.gridView.setup(style: paperStyle, columns: gridColumns, paper: paper)

        // Store current ink properties so the coordinator can commit straight lines and shapes.
        let inkColor = inkUIColor(from: penColor)
        coord.currentInkColor = inkColor
        coord.currentPenWidth = CGFloat(penWidth)

        // Apply tool to PKCanvasView.
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

        // Activate or deactivate the shape overlay.
        shapeOvr.inkColor     = inkColor
        shapeOvr.inkWidth     = CGFloat(penWidth)
        shapeOvr.scrollOffset = canvas.contentOffset.y
        shapeOvr.shapeKind    = activeShapeKind
        if activeTool == .shape {
            shapeOvr.activate()
        } else {
            shapeOvr.deactivate()
        }
    }

    private func applyTool(to canvas: CanvasView, tool: DrawingTool, color: UIColor, width: CGFloat) {
        switch tool {
        case .pen, .straightLine, .shape:
                                  canvas.tool = PKInkingTool(.pen,         color: color, width: width)
        case .marker:             canvas.tool = PKInkingTool(.marker,      color: color, width: width * 4)
        case .highlighter:        canvas.tool = PKInkingTool(.marker, color: color.withAlphaComponent(0.42), width: width * 8)
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

        weak var shapeOverlay: ShapeOverlay?

        var activeTool: DrawingTool = .pen
        var isDrawing  = false
        private var isResettingCanvas = false
        private var liveCheckTask: Task<Void, Never>? = nil

        // Ink state used when building straight-line and shape PKStrokes.
        var currentInkColor: UIColor = .black
        var currentPenWidth: CGFloat = 3

        // The PKTool that was on the canvas before squeeze/double-tap activated
        // the eraser. Stored here so we can restore it directly on the canvas the
        // instant the squeeze releases, without waiting for SwiftUI's update cycle.
        var toolBeforeSqueeze: PKTool? = nil

        var isDarkPaper = false

        var onDoubleTapMenu: (CGPoint, UIImage) -> Void = { _, _ in }
        var onLiveCheckRegion: (CGPoint, UIImage) -> Void = { _, _ in }
        var onPencilSqueezeBegan: () -> Void = {}
        var onPencilSqueezeEnded: () -> Void = {}
        var onRequestTool: (DrawingTool) -> Void = { _ in }
        var onSwitchColor: () -> Void = {}
        var onShowToolPalette: (CGPoint) -> Void = { _ in }
        var onNeedsRecreate: () -> Void = {}

        /// Updated live while the Pencil hovers above the canvas (supported
        /// hardware only). Left stale — i.e. "last known" — once the Pencil
        /// moves out of hover range or touches down to draw.
        private var lastHoverViewPosition: CGPoint? = nil

        init(page: Page) { self.page = page }

        // Gesture recognizer delegate — recognizers fire simultaneously.
        func gestureRecognizer(_ gr: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ gr: UIGestureRecognizer,
                               shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }

        // MARK: Finger double-tap → quick-action menu

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let canvas = canvas else { return }
            let contentPos = gesture.location(in: canvas)
            let region = CGRect(x: contentPos.x - 400, y: contentPos.y - 220, width: 800, height: 440)
            onDoubleTapMenu(viewPos(for: gesture, in: canvas),
                            captureOCRImage(from: canvas.drawing, region: region))
        }

        // MARK: Multi-touch undo/redo (Settings → Writing → Gestures & Touch)

        @objc func handleTwoFingerUndo(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  UserDefaults.standard.bool(forKey: "settings.gestures.twoFingerUndo") else { return }
            canvas?.undoManager?.undo()
        }

        @objc func handleThreeFingerRedo(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  UserDefaults.standard.bool(forKey: "settings.gestures.threeFingerRedo") else { return }
            canvas?.undoManager?.redo()
        }

        // MARK: Pen button action mapping (Settings → Writing → Pen Buttons)

        /// Performs a one-shot action for every `PenButtonAction` other than
        /// `.toggleEraser`, which needs hold/restore state handled by the caller.
        private func performOneShotPenButtonAction(_ raw: String) {
            switch raw {
            case "undo":         canvas?.undoManager?.undo()
            case "redo":         canvas?.undoManager?.redo()
            case "switchColors": onSwitchColor()
            case "triggerLasso": onRequestTool(.lasso)
            case "showToolPalette": onShowToolPalette(resolvedPencilViewPosition())
            default: break // "none" or unrecognized
            }
        }

        private func viewPos(for gesture: UIGestureRecognizer, in canvas: CanvasView) -> CGPoint {
            let p = gesture.location(in: canvas)
            return CGPoint(x: p.x, y: p.y - canvas.contentOffset.y)
        }

        // MARK: Pencil hover tracking (for palette positioning)

        @objc func handleHover(_ gesture: UIHoverGestureRecognizer) {
            guard let canvas = canvas else { return }
            switch gesture.state {
            case .began, .changed:
                let p = gesture.location(in: canvas)
                lastHoverViewPosition = CGPoint(x: p.x, y: p.y - canvas.contentOffset.y)
            default:
                break // Pencil moved out of hover range — keep the last known spot.
            }
        }

        /// Where the Pencil currently is (if hovering), or was last known to
        /// be (last hover point, or failing that the end of the most recent
        /// stroke), or the middle of the visible canvas if none of that is
        /// available yet.
        func resolvedPencilViewPosition() -> CGPoint {
            if let hover = lastHoverViewPosition { return hover }
            if let canvas = canvas,
               let lastPoint = canvas.drawing.strokes.last?.path.last?.location {
                return CGPoint(x: lastPoint.x, y: lastPoint.y - canvas.contentOffset.y)
            }
            if let canvas = canvas {
                return CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
            }
            return CGPoint(x: 200, y: 200)
        }

        private func captureOCRImage(from drawing: PKDrawing, region: CGRect) -> UIImage {
            // Always render in light mode so PencilKit uses the stored (light-resolved)
            // ink colors regardless of the system's dark/light setting.
            // On dark paper the ink is light; we composite on black then invert for OCR.
            // Scale 3 (not 2) gives Vision sharper glyph edges to disambiguate
            // visually similar handwritten characters.
            var inkImage = UIImage()
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                inkImage = drawing.image(from: region, scale: 3)
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

        // MARK: Shape stroke commit

        func commitShape(from start: CGPoint, to end: CGPoint) {
            guard let canvas = canvas else { return }
            let kind = shapeOverlay?.shapeKind ?? .rectangle
            let strokes = shapeStrokes(from: start, to: end, kind: kind)
            guard !strokes.isEmpty else { return }
            var drawing = canvas.drawing
            drawing.strokes.append(contentsOf: strokes)
            canvas.drawing = drawing
        }

        private func shapeStrokes(from start: CGPoint, to end: CGPoint, kind: ShapeKind) -> [PKStroke] {
            let rect = CGRect(
                x: Swift.min(start.x, end.x),
                y: Swift.min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            guard rect.width > 4 || rect.height > 4 else { return [] }

            let ink = PKInk(.pen, color: currentInkColor)

            func mkStroke(_ pts: [CGPoint]) -> PKStroke {
                let n = pts.count
                let sPts = pts.enumerated().map { i, p in
                    PKStrokePoint(
                        location: p,
                        timeOffset: Double(i) / Double(Swift.max(n - 1, 1)),
                        size: CGSize(width: currentPenWidth, height: currentPenWidth),
                        opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                    )
                }
                return PKStroke(ink: ink, path: PKStrokePath(controlPoints: sPts, creationDate: Date()))
            }

            func lerp(_ a: CGPoint, _ b: CGPoint) -> [CGPoint] {
                let len = hypot(b.x - a.x, b.y - a.y)
                let n = Swift.max(3, Int(len / 8) + 2)
                return (0..<n).map { i in
                    let t = CGFloat(i) / CGFloat(n - 1)
                    return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                }
            }

            func ellipsePts(in r: CGRect, count: Int = 72) -> [CGPoint] {
                (0...count).map { i in
                    let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(count)
                    return CGPoint(x: r.midX + r.width / 2 * cos(t),
                                   y: r.midY + r.height / 2 * sin(t))
                }
            }

            switch kind {
            case .rectangle:
                let tl = CGPoint(x: rect.minX, y: rect.minY)
                let tr = CGPoint(x: rect.maxX, y: rect.minY)
                let br = CGPoint(x: rect.maxX, y: rect.maxY)
                let bl = CGPoint(x: rect.minX, y: rect.maxY)
                return [mkStroke(lerp(tl, tr)), mkStroke(lerp(tr, br)),
                        mkStroke(lerp(br, bl)), mkStroke(lerp(bl, tl))]

            case .circle:
                let side = Swift.min(rect.width, rect.height)
                let cr = CGRect(x: rect.midX - side/2, y: rect.midY - side/2, width: side, height: side)
                return [mkStroke(ellipsePts(in: cr))]

            case .oval:
                return [mkStroke(ellipsePts(in: rect))]

            case .arrow:
                let angle = atan2(end.y - start.y, end.x - start.x)
                let headLen = Swift.max(20, hypot(end.x - start.x, end.y - start.y) * 0.2)
                let a1 = angle + .pi * 5 / 6
                let a2 = angle - .pi * 5 / 6
                let h1 = CGPoint(x: end.x + headLen * cos(a1), y: end.y + headLen * sin(a1))
                let h2 = CGPoint(x: end.x + headLen * cos(a2), y: end.y + headLen * sin(a2))
                return [mkStroke(lerp(start, end)),
                        mkStroke(lerp(end, h1)),
                        mkStroke(lerp(end, h2))]

            case .triangle:
                let p1 = CGPoint(x: rect.midX, y: rect.minY)
                let p2 = CGPoint(x: rect.minX, y: rect.maxY)
                let p3 = CGPoint(x: rect.maxX, y: rect.maxY)
                return [mkStroke(lerp(p1, p2)), mkStroke(lerp(p2, p3)), mkStroke(lerp(p3, p1))]
            }
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { isDrawing = true }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { isDrawing = false }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            gridView?.scrollOffset = scrollView.contentOffset.y
            gridView?.setNeedsDisplay()
            straightLineOverlay?.scrollOffset = scrollView.contentOffset.y
            shapeOverlay?.scrollOffset = scrollView.contentOffset.y

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

                // PKCanvasView enters a zombie state when the last stroke is
                // erased — it keeps accepting touches for panning/menus but
                // silently stops turning pencil input into new strokes.
                // In-place workarounds (reassigning .drawing/.tool, toggling
                // isUserInteractionEnabled) do not reliably recover it. The
                // only thing confirmed to fix it is a full teardown/rebuild
                // (e.g. leaving and reopening the note), so rather than
                // patch this PKCanvasView in place, ask CanvasWorkspace to
                // recreate it from scratch via a fresh `.id()`. Deferred one
                // run loop cycle so PencilKit's own stroke-count update
                // finishes first; the flag blocks this same (soon-discarded)
                // coordinator from re-entering before that happens.
                if canvasView.drawing.strokes.isEmpty {
                    isResettingCanvas = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onNeedsRecreate()
                    }
                }
            }
            scheduleLiveCheck(for: canvasView)
        }

        // MARK: Live equation checking (debounced)

        /// Settings → Tutor & Recognition → Real-Time Equation Checking.
        /// Defaults to true when the key hasn't been written yet, since the
        /// Settings toggle itself defaults to on.
        private static var liveReviewEnabled: Bool {
            (UserDefaults.standard.object(forKey: "settings.tutor.liveReviewEnabled") as? Bool) ?? true
        }

        /// Cancels any pending check and starts a new one ~1s out, so rapid
        /// strokes don't trigger a check per-stroke — only once the user
        /// pauses. Captures the actual bounding box of the whole equation
        /// (not a fixed-size box around just the last stroke) so long or wide
        /// equations aren't clipped before OCR ever sees them — a major
        /// source of misreads, since a clipped character reads as garbage.
        private func scheduleLiveCheck(for canvasView: PKCanvasView) {
            liveCheckTask?.cancel()
            guard Self.liveReviewEnabled else { return }
            guard let lastStroke = canvasView.drawing.strokes.last else { return }
            let drawing = canvasView.drawing
            let lastBounds = lastStroke.renderBounds
            // Generous search window around the last stroke to find the rest
            // of the equation it belongs to.
            let searchRegion = lastBounds.insetBy(dx: -400, dy: -220)

            // Union the bounds of every stroke inside the search window (not
            // just the last one) so both the OCR capture and the badge anchor
            // cover the whole equation rather than wherever the most recent
            // stroke happens to sit within it.
            let equationBounds = drawing.strokes
                .map(\.renderBounds)
                .filter { searchRegion.intersects($0) }
                .reduce(lastBounds) { $0.union($1) }
            let topLeft = CGPoint(x: equationBounds.minX, y: equationBounds.minY)
            // Pad the actual capture so characters right at the equation's
            // edge (a leading "-", a trailing digit) aren't clipped.
            let captureRegion = equationBounds.insetBy(dx: -50, dy: -50)

            liveCheckTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, let canvas = self.canvas else { return }
                let image = self.captureOCRImage(from: drawing, region: captureRegion)
                let viewPos = CGPoint(x: topLeft.x, y: topLeft.y - canvas.contentOffset.y)
                await MainActor.run {
                    self.onLiveCheckRegion(viewPos, image)
                }
            }
        }

        private func grow(_ c: CanvasView, by delta: CGFloat) { grow(c, to: c.contentSize.height + delta) }
        private func grow(_ c: CanvasView, to height: CGFloat) {
            guard c.bounds.width > 0 else { return }
            c.contentSize = CGSize(width: c.bounds.width, height: height)
        }

        // MARK: UIPencilInteractionDelegate

        // Apple Pencil 2 double-tap. Default action toggles the eraser on/off;
        // Settings → Writing → Pen Buttons can remap it to Undo/Redo/Switch
        // Colors/Trigger Lasso/No Action instead.
        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            let action = UserDefaults.standard.string(forKey: "settings.penButtons.doubleClick") ?? "toggleEraser"
            guard action == "toggleEraser" else {
                performOneShotPenButtonAction(action)
                return
            }
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

        // Apple Pencil Pro squeeze. Default action holds the eraser while
        // squeezed; Settings → Writing → Pen Buttons can remap the squeeze
        // to a one-shot Undo/Redo/Switch Colors/Trigger Lasso/No Action instead.
        func pencilInteraction(_ interaction: UIPencilInteraction,
                               didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            let action = UserDefaults.standard.string(forKey: "settings.penButtons.singleClick")
                ?? PenButtonAction.showToolPalette.rawValue
            switch squeeze.phase {
            case .began:
                guard action == "toggleEraser" else {
                    performOneShotPenButtonAction(action)
                    return
                }
                toolBeforeSqueeze = canvas?.tool
                canvas?.tool = PKEraserTool(.vector)
                onPencilSqueezeBegan()
            case .ended, .cancelled:
                guard action == "toggleEraser" else { return }
                if let saved = toolBeforeSqueeze { canvas?.tool = saved }
                toolBeforeSqueeze = nil
                onPencilSqueezeEnded()
            default: break
            }
        }
    }
}

// MARK: - CanvasWrapper

/// Container: GridContentView (z=0) → CanvasView (z=1) → StraightLineOverlay (z=2) → ShapeOverlay (z=3).
/// Handles pinch-to-zoom by scaling the entire wrapper (grid + ink scale together).
final class CanvasWrapper: UIView {
    let canvas: CanvasView
    let gridView: GridContentView
    let straightLineOverlay: StraightLineOverlay
    let shapeOverlay: ShapeOverlay

    private var zoomScale: CGFloat = 1.0
    private var zoomTx: CGFloat = 0
    private var zoomTy: CGFloat = 0
    private var pinchStartScale: CGFloat = 1.0
    private var pinchAnchorLocal: CGPoint = .zero   // pinch center in untransformed canvas coords
    private var pinchAnchorScreen: CGPoint = .zero  // pinch center in superview coords

    init() {
        canvas              = CanvasView()
        gridView            = GridContentView()
        straightLineOverlay = StraightLineOverlay()
        shapeOverlay        = ShapeOverlay()
        super.init(frame: .zero)
        addSubview(gridView)             // z = 0
        addSubview(canvas)               // z = 1
        addSubview(straightLineOverlay)  // z = 2, intercepts pencil touches when active
        addSubview(shapeOverlay)         // z = 3, intercepts pencil touches for shape drawing

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        addGestureRecognizer(pinch)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let sv = superview else { return }

        switch gesture.state {
        case .began:
            pinchStartScale   = zoomScale
            pinchAnchorScreen = gesture.location(in: sv)

            // Invert the current transform to find which untransformed canvas point
            // sits under the pinch. Formula: local = (screen - center - tx) / scale + bounds.mid
            pinchAnchorLocal = CGPoint(
                x: (pinchAnchorScreen.x - center.x - zoomTx) / zoomScale + bounds.midX,
                y: (pinchAnchorScreen.y - center.y - zoomTy) / zoomScale + bounds.midY
            )

        case .changed:
            let s = Swift.min(Swift.max(pinchStartScale * gesture.scale, 1.0), 4.0)

            // Build a scale + translate transform that keeps pinchAnchorLocal
            // fixed at pinchAnchorScreen regardless of scale.
            var t = CGAffineTransform.identity
            if s > 1.0 {
                t.a  = s;  t.d  = s
                t.tx = pinchAnchorScreen.x - center.x - s * (pinchAnchorLocal.x - bounds.midX)
                t.ty = pinchAnchorScreen.y - center.y - s * (pinchAnchorLocal.y - bounds.midY)
            }
            // s == 1.0: identity (t already is identity, which resets any translation)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            transform = t
            CATransaction.commit()

        case .ended, .cancelled:
            zoomScale = Swift.min(Swift.max(pinchStartScale * gesture.scale, 1.0), 4.0)
            if zoomScale <= 1.0 {
                zoomTx = 0; zoomTy = 0
            } else {
                zoomTx = transform.tx
                zoomTy = transform.ty
            }

        default: break
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame              = bounds
        gridView.frame            = bounds
        straightLineOverlay.frame = bounds
        shapeOverlay.frame        = bounds
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

// MARK: - ShapeOverlay

/// Transparent view (z=3) that intercepts pencil touches when the shape tool is active.
/// Shows a live CAShapeLayer preview, then calls onCommit(start, end) in content-space
/// coordinates when the pencil lifts. Finger touches fall through to the canvas.
final class ShapeOverlay: UIView {
    var onCommit: ((CGPoint, CGPoint) -> Void)?
    var inkColor: UIColor = .black { didSet { lineLayer.strokeColor = inkColor.cgColor } }
    var inkWidth: CGFloat = 3     { didSet { lineLayer.lineWidth = inkWidth } }
    var scrollOffset: CGFloat = 0
    var shapeKind: ShapeKind = .rectangle

    private var isCapturing = false
    private var startPoint: CGPoint?
    private let lineLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        lineLayer.fillColor  = UIColor.clear.cgColor
        lineLayer.lineCap    = .round
        lineLayer.lineJoin   = .round
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

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isCapturing, bounds.contains(point) else { return nil }
        if let touch = event?.allTouches?.first, touch.type != .pencil { return nil }
        return self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first(where: { $0.type == .pencil }) else { return }
        startPoint = t.location(in: self)
        updatePreview(from: startPoint!, to: startPoint!)
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
        clearPreview(); startPoint = nil
    }

    private func updatePreview(from start: CGPoint, to current: CGPoint) {
        let path = previewPath(from: start, to: current)
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

    private func previewPath(from start: CGPoint, to end: CGPoint) -> CGPath {
        let rect = CGRect(
            x: Swift.min(start.x, end.x), y: Swift.min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
        let path = CGMutablePath()
        switch shapeKind {
        case .rectangle:
            path.addRect(rect)
        case .circle:
            let side = Swift.min(rect.width, rect.height)
            path.addEllipse(in: CGRect(x: rect.midX - side/2, y: rect.midY - side/2,
                                       width: side, height: side))
        case .oval:
            path.addEllipse(in: rect)
        case .arrow:
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLen = Swift.max(20, hypot(end.x - start.x, end.y - start.y) * 0.2)
            let a1 = angle + .pi * 5 / 6
            let a2 = angle - .pi * 5 / 6
            path.move(to: start); path.addLine(to: end)
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x + headLen * cos(a1), y: end.y + headLen * sin(a1)))
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x + headLen * cos(a2), y: end.y + headLen * sin(a2)))
        case .triangle:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }

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

    // Settings → Paper & Layout → Margins / Page Size, re-read on every
    // setup() call (which SwiftUI drives via updateUIView often enough to
    // pick up changes live).
    private var marginPt: CGFloat = 0
    private var pageHeightPt: CGFloat? = nil

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

        let marginRaw = UserDefaults.standard.object(forKey: "settings.paper.margin") as? Double
        marginPt = CGFloat(marginRaw ?? 24.0)

        let dimRaw = UserDefaults.standard.string(forKey: "settings.paper.pageDimension")
            ?? PageDimension.infinite.rawValue
        switch PageDimension(rawValue: dimRaw) ?? .infinite {
        case .a4:       pageHeightPt = 1123   // A4 (11.69in) at 96pt/in
        case .letter:   pageHeightPt = 1056   // Letter (11in) at 96pt/in
        case .infinite: pageHeightPt = nil
        }

        // Transparent, not the paper color: CanvasWorkspace paints the paper
        // itself as a backdrop behind everything, including photos — this
        // view (grid lines + whatever ink sits above it) must stay
        // see-through so an imported photo positioned behind the ink layer
        // isn't hidden behind an opaque fill here.
        backgroundColor          = .clear
        isUserInteractionEnabled = false
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 0, let ctx = UIGraphicsGetCurrentContext() else { return }

        let spacing = bounds.width / CGFloat(currentColumns)

        if currentStyle != .blank, spacing >= 3 {
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

            case .checklist:
                // Ten fixed rows, each a ruled line prefixed by an empty
                // checkbox square — the user checks one off simply by
                // drawing a mark through it with the Pencil, same as a
                // paper checklist. An "Other Reminders" header and
                // continued ruled lines follow for anything else.
                let checklistRows = 10
                let checkboxSize = min(spacing * 0.5, 18)
                let checkboxInsetX: CGFloat = marginPt > 0 ? marginPt * 0.4 : 12

                for i in 0..<checklistRows {
                    let lineY = CGFloat(i + 1) * spacing - scrollOffset
                    guard lineY >= rect.minY - spacing, lineY <= rect.maxY + 0.5 else { continue }

                    ctx.move(to: CGPoint(x: checkboxInsetX + checkboxSize + 8, y: lineY))
                    ctx.addLine(to: CGPoint(x: bounds.width, y: lineY))
                    ctx.strokePath()

                    let box = CGRect(x: checkboxInsetX, y: lineY - checkboxSize - 2,
                                      width: checkboxSize, height: checkboxSize)
                    ctx.stroke(box)
                }

                let headerY = CGFloat(checklistRows) * spacing + spacing * 0.6 - scrollOffset
                if headerY >= rect.minY - 30, headerY <= rect.maxY + 30 {
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 15),
                        .foregroundColor: lineColor.withAlphaComponent(1.0)
                    ]
                    ("Other Reminders" as NSString).draw(at: CGPoint(x: checkboxInsetX, y: headerY), withAttributes: attrs)
                }

                // NSString.draw(at:withAttributes:) leaves the context's
                // stroke color/width in an undefined state, so the
                // continuation lines below must reassert them explicitly —
                // otherwise they can render fully opaque instead of the
                // same faint guide color as the rows above.
                ctx.setStrokeColor(lineColor.cgColor)
                ctx.setLineWidth(0.5)

                let bodyStartRow = checklistRows + 2
                let kBody = max(bodyStartRow, Int(ceil((rect.minY + scrollOffset) / spacing)))
                var y = CGFloat(kBody) * spacing - scrollOffset
                while y <= rect.maxY + 0.5 {
                    ctx.move(to: CGPoint(x: 0, y: y))
                    ctx.addLine(to: CGPoint(x: bounds.width, y: y))
                    y += spacing
                }
                ctx.strokePath()
            }
        }

        // Page-break guides (Settings → Paper & Layout → Page Size). Purely
        // visual — the canvas still scrolls continuously rather than paginating.
        if let pageH = pageHeightPt, pageH > 0 {
            ctx.saveGState()
            ctx.setStrokeColor(UIColor.systemOrange.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            let kMin = Int(floor((rect.minY + scrollOffset) / pageH))
            var y = CGFloat(kMin) * pageH - scrollOffset
            while y <= rect.maxY + 0.5 {
                if y >= rect.minY - 0.5 {
                    ctx.move(to: CGPoint(x: 0, y: y))
                    ctx.addLine(to: CGPoint(x: bounds.width, y: y))
                }
                y += pageH
            }
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Margin guides (Settings → Paper & Layout → Margins).
        if marginPt > 0 {
            ctx.saveGState()
            ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.3).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [3, 3])
            for x in [marginPt, bounds.width - marginPt] {
                ctx.move(to: CGPoint(x: x, y: rect.minY))
                ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
    }
}
#endif
