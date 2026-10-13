//
//  EquationGraphView.swift
//  Tolerance
//
//  Floating graph card.
//
//  • 2-D mode  — y = f(x):    Swift Charts line graph with x-range sliders.
//  • 3-D mode  — z = f(x,y):  SceneKit surface mesh with free camera orbit,
//                              zoom, and pan.  The mode is chosen automatically
//                              based on whether the expression contains 'y'.
//
//  The expression field is always editable so the user can correct OCR errors
//  or type an expression from scratch.
//

#if os(iOS)
import SwiftUI
import Charts
import SceneKit

// MARK: - Main container

struct EquationGraphView: View {
    let equationText: String      // raw OCR text (shown as subtitle)
    let expression: String        // initial expression from OCR (seed value)

    // Floating-card callbacks (nil = card is embedded, not floating).
    // onHeaderDrag shifts the card's center by a CGSize delta — used both
    // for dragging the grab bar AND for keeping the opposite edge visually
    // anchored while resizing (see the edge-drag gestures below).
    let onHeaderDrag: ((CGSize) -> Void)?
    // (widthDelta, centerXDelta) — see the comment on leftEdgeDrag/rightEdgeDrag
    // for why these two can't be derived from one another.
    let onWidthDelta: ((CGFloat, CGFloat) -> Void)?

    @State private var editExpr: String

    // 2-D state
    @State private var xMin: Double = -10
    @State private var xMax: Double = 10
    @State private var graphHeight: CGFloat = 220

    // Cached plot samples — recomputed only when the expression or x-range
    // actually changes (see recomputePlotData()), NOT as a plain computed
    // property. plotData used to be `private var plotData: [DataPoint] { ... }`,
    // re-sampling the expression 300 times on every single body evaluation —
    // including every tiny drag-position update while moving this card —
    // which was the actual cause of the card visibly lagging behind the
    // finger while dragging.
    @State private var plotData: [DataPoint] = []

    // Calculator keypad — collapsed by default; revealed by tapping the
    // button below the expression row.
    @State private var showCalculatorKeypad = false

    // 3-D state — domain ±range in both x and y
    @State private var axisRange: Double = 5

    // 2-D draw-in animation (0 = hidden, 1 = fully revealed)
    @State private var chartReveal: CGFloat = 0

    // Graph dimension override
    private enum GraphDimension: Equatable { case auto, force2D, force3D }
    @State private var modeOverride: GraphDimension

    // Hold-to-resize mode — entered/exited by long-pressing the grab bar.
    @State private var isResizeMode = false

    // Drag delta tracking (DragGesture gives cumulative translation; we send incremental deltas)
    @State private var prevLeftDrag:   CGFloat = 0
    @State private var prevRightDrag:  CGFloat = 0
    @State private var prevTopDrag:    CGFloat = 0
    @State private var prevBottomDrag: CGFloat = 0

    init(equationText: String, expression: String, forceIs3D: Bool? = nil,
         onHeaderDrag: ((CGSize) -> Void)? = nil,
         onWidthDelta: ((CGFloat, CGFloat) -> Void)? = nil) {
        self.equationText    = equationText
        self.expression      = expression
        self._editExpr       = State(initialValue: expression)
        self.onHeaderDrag    = onHeaderDrag
        self.onWidthDelta    = onWidthDelta
        switch forceIs3D {
        case .some(true):  self._modeOverride = State(initialValue: .force3D)
        case .some(false): self._modeOverride = State(initialValue: .force2D)
        case .none:        self._modeOverride = State(initialValue: .auto)
        }
    }

    private var is3D: Bool {
        switch modeOverride {
        case .auto:    return MathEvaluator.is3DExpression(editExpr)
        case .force2D: return false
        case .force3D: return true
        }
    }

    // A bare Shape with no explicit frame reports a very large/flexible
    // ideal size, which blows up the surrounding ZStack to fill all
    // available space instead of matching cardContent's actual footprint
    // (that's why the dashed outline/handles used to render detached,
    // spanning far more than the card). Measuring cardContent explicitly
    // and pinning the outline/handles to that exact size fixes it.
    @State private var cardSize: CGSize = .zero

    var body: some View {
        ZStack {
            // Outline of the card's normal (unscaled) bounds — only visible
            // while hold-to-resize mode is active. scaleEffect below is a
            // purely visual transform that doesn't shrink cardContent's
            // measured size, so this outline and the edge handles stay
            // pinned to its un-shrunk bounds even while it visually shrinks.
            if isResizeMode {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.accentColor.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: cardSize.width, height: cardSize.height)
            }

            cardContent
                .scaleEffect(isResizeMode ? 0.94 : 1)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }

            if isResizeMode {
                resizeHandles
                    .frame(width: cardSize.width, height: cardSize.height)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isResizeMode)
        .onAppear { recomputePlotData() }
        .onChange(of: xMin) { _, _ in recomputePlotData() }
        .onChange(of: xMax) { _, _ in recomputePlotData() }
        .onChange(of: editExpr) { _, _ in recomputePlotData() }
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            grabBar
            expressionRow
            calculatorToggleRow
            if showCalculatorKeypad {
                FunctionKeyboardStrip { key in
                    editExpr += key
                }
                EquationKeypad { key in editExpr += key }
            }
            Divider()
            if editExpr.trimmingCharacters(in: .whitespaces).isEmpty {
                emptyPrompt
            } else if is3D {
                Graph3DScene(expression: editExpr, range: axisRange)
                    .frame(height: graphHeight)
                Divider()
                controls3D
                hint3D
            } else {
                chartArea
                Divider()
                controls2D
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.blue.opacity(0.35), lineWidth: 1))
        .shadow(radius: 18, y: 6)
    }

    // MARK: - Resize handles (hold-to-resize mode)

    /// Four independent edge handles — drag the left/right handle to change
    /// width only, top/bottom to change height only, each keeping the
    /// OPPOSITE edge visually anchored (like dragging a window's edge on
    /// the Mac). Positioned via GeometryReader against cardContent's
    /// unscaled bounds (see the comment in `body`).
    private var resizeHandles: some View {
        GeometryReader { geo in
            resizeHandleIcon("arrow.left.and.right")
                .position(x: 0, y: geo.size.height / 2)
                .gesture(leftEdgeDrag)
            resizeHandleIcon("arrow.left.and.right")
                .position(x: geo.size.width, y: geo.size.height / 2)
                .gesture(rightEdgeDrag)
            resizeHandleIcon("arrow.up.and.down")
                .position(x: geo.size.width / 2, y: 0)
                .gesture(topEdgeDrag)
            resizeHandleIcon("arrow.up.and.down")
                .position(x: geo.size.width / 2, y: geo.size.height)
                .gesture(bottomEdgeDrag)
        }
    }

    private func resizeHandleIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Color.accentColor, in: Circle())
            .shadow(radius: 3)
            .contentShape(Circle().inset(by: -8))   // easier to grab than the visible dot
    }

    // Width resize's opposite-edge anchoring is handled entirely by the
    // parent's onWidthDelta closure. The center-x shift needed to keep the
    // opposite edge fixed is ALWAYS +rawDelta/2 regardless of which edge is
    // being dragged, but the width change flips sign (-rawDelta for the
    // left edge, +rawDelta for the right) — those two values are NOT a
    // fixed ratio of each other, so both must be passed explicitly rather
    // than having the parent derive one from the other.
    private var leftEdgeDrag: some Gesture {
        DragGesture()
            .onChanged { v in
                let delta = v.translation.width - prevLeftDrag
                prevLeftDrag = v.translation.width
                onWidthDelta?(-delta, delta / 2)
            }
            .onEnded { _ in prevLeftDrag = 0 }
    }

    private var rightEdgeDrag: some Gesture {
        DragGesture()
            .onChanged { v in
                let delta = v.translation.width - prevRightDrag
                prevRightDrag = v.translation.width
                onWidthDelta?(delta, delta / 2)
            }
            .onEnded { _ in prevRightDrag = 0 }
    }

    private var topEdgeDrag: some Gesture {
        DragGesture()
            .onChanged { v in
                let delta = v.translation.height - prevTopDrag
                prevTopDrag = v.translation.height
                graphHeight = min(700, max(160, graphHeight - delta))
                onHeaderDrag?(CGSize(width: 0, height: delta / 2))
            }
            .onEnded { _ in prevTopDrag = 0 }
    }

    private var bottomEdgeDrag: some Gesture {
        DragGesture()
            .onChanged { v in
                let delta = v.translation.height - prevBottomDrag
                prevBottomDrag = v.translation.height
                graphHeight = min(700, max(160, graphHeight + delta))
                onHeaderDrag?(CGSize(width: 0, height: delta / 2))
            }
            .onEnded { _ in prevBottomDrag = 0 }
    }

    // MARK: - Grab bar

    /// Replaces the old title header entirely. A single centered capsule,
    /// about a quarter of the card's width, is the only way to move (plain
    /// drag) or resize (long-press to toggle hold-to-resize mode, see
    /// `isResizeMode`) the card.
    private var grabBar: some View {
        GeometryReader { geo in
            ZStack {
                if onHeaderDrag != nil {
                    DragHandleRepresentable(
                        onPanDelta: { delta in onHeaderDrag?(delta) },
                        onLongPress: { withAnimation(.spring(response: 0.3)) { isResizeMode.toggle() } }
                    )
                }
                Capsule()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: geo.size.width * 0.25, height: 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 22)
    }

    // MARK: - Expression editor row

    private var expressionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "function")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 16)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(editExpr.isEmpty ? "e.g. cos(sqrt(x^2+y^2))" : editExpr)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(editExpr.isEmpty ? .tertiary : .primary)
            }
            Spacer(minLength: 0)
            if !editExpr.isEmpty {
                Button {
                    editExpr.removeLast()
                } label: {
                    Image(systemName: "delete.backward")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            // Reset button — only visible when user has drifted from OCR suggestion
            if !editExpr.isEmpty && editExpr != expression {
                Button {
                    editExpr = expression
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Calculator keypad toggle

    /// The function-key strip + numeric keypad are hidden by default (they
    /// used to always take up a big chunk of the card's height); tapping
    /// this reveals them right below the expression row.
    private var calculatorToggleRow: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3)) { showCalculatorKeypad.toggle() }
            } label: {
                Image(systemName: "sum")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(showCalculatorKeypad ? Color.accentColor : Color.secondary)
                    .frame(width: 26, height: 22)
                    .background(showCalculatorKeypad ? Color.accentColor.opacity(0.15) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, 2)
        .background(Color(.systemGray6))
    }

    // MARK: - Empty state

    private var emptyPrompt: some View {
        ContentUnavailableView {
            Label("Enter an Expression", systemImage: "function")
        } description: {
            Text("Type in the field above.\nUse x for 2-D  (e.g. x^2 + 1)\nUse x and y for 3-D  (e.g. cos(sqrt(x^2+y^2)))")
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - 3-D hint

    private var hint3D: some View {
        HStack {
            Image(systemName: "hand.draw").font(.caption2)
            Text("Drag to orbit · Pinch to zoom · 2-finger drag to pan")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - 2-D chart

    @ViewBuilder
    private var chartArea: some View {
        if plotData.isEmpty {
            ContentUnavailableView {
                Label("Can't Plot", systemImage: "chart.line.uptrend.xyaxis.circle")
            } description: {
                Text("Expression couldn't be evaluated. Check the expression field above.")
            }
            .frame(maxHeight: .infinity)
        } else {
            Chart(plotData) { pt in
                LineMark(
                    x: .value("x", pt.x),
                    y: .value("y", pt.y)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .position(by: .value("Segment", pt.segmentID))
            }
            .chartXScale(domain: xMin...xMax)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) {
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.35))
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.35))
                    AxisValueLabel()
                }
            }
            .frame(height: graphHeight)
            .padding(12)
            .mask {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle()
                            .frame(width: geo.size.width * chartReveal)
                        Spacer(minLength: 0)
                    }
                }
            }
            .task(id: editExpr) {
                chartReveal = 0
                try? await Task.sleep(nanoseconds: 40_000_000)
                withAnimation(.easeInOut(duration: 0.7)) { chartReveal = 1 }
            }
        }
    }

    private struct DataPoint: Identifiable {
        let id = UUID()
        let x, y: Double
        let segmentID: Int
    }

    private func recomputePlotData() {
        guard xMax > xMin, !editExpr.isEmpty else { plotData = []; return }
        let n = 300
        let dx = (xMax - xMin) / Double(n)
        var pts: [DataPoint] = []
        var prevY: Double? = nil
        var seg = 0
        for k in 0...n {
            let xv = xMin + Double(k) * dx
            guard let yv = MathEvaluator.evaluate(editExpr, x: xv),
                  yv.isFinite else { prevY = nil; seg += 1; continue }
            if let p = prevY, abs(yv - p) > 500 { seg += 1 }
            prevY = yv
            pts.append(DataPoint(x: xv, y: yv, segmentID: seg))
        }
        plotData = pts
    }

    private var yDomain: ClosedRange<Double> {
        let ys = plotData.map(\.y).filter(\.isFinite)
        guard let lo = ys.min(), let hi = ys.max(), lo <= hi else { return -10...10 }
        let pad = max((hi - lo) * 0.12, 0.5)
        return (lo - pad)...(hi + pad)
    }

    private var controls3D: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.and.right.square")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("x, y axis")
                    .font(.caption2).foregroundStyle(.secondary)
                Slider(value: $axisRange, in: 2...100, step: 1)
                Text("±\(axisRange, specifier: "%.0f")")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.blue)
                    .frame(width: 36)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var controls2D: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.and.right").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $xMin, in: -500...(-0.5))
                Text("\(xMin, specifier: "%.0f") → \(xMax, specifier: "%.0f")")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.blue)
                    .frame(width: 72)
                Slider(value: $xMax, in: 0.5...500)
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.and.down").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $graphHeight, in: 220...520, step: 20)
                Text("Height").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// Native UIKit pan + long-press recognizer used on the grab bar — mirrors
/// `PhotoGrabZoneRepresentable`'s approach of hosting multiple UIKit
/// recognizers side by side (with a delegate allowing simultaneous
/// recognition), reporting true incremental pan deltas (translation reset
/// to zero every tick) straight from UIKit's touch handling rather than
/// through SwiftUI's `DragGesture`. Long-press toggles hold-to-resize mode.
private struct DragHandleRepresentable: UIViewRepresentable {
    let onPanDelta: (CGSize) -> Void
    let onLongPress: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        pan.delegate = context.coordinator
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(longPress)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onPanDelta = onPanDelta
        context.coordinator.onLongPress = onLongPress
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onPanDelta: ((CGSize) -> Void)?
        var onLongPress: (() -> Void)?

        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            guard gr.state == .changed else { return }
            let translation = gr.translation(in: gr.view)
            onPanDelta?(CGSize(width: translation.x, height: translation.y))
            gr.setTranslation(.zero, in: gr.view)
        }

        @objc func handleLongPress(_ gr: UILongPressGestureRecognizer) {
            guard gr.state == .began else { return }
            onLongPress?()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

// MARK: - 3-D SceneKit Surface

struct Graph3DScene: UIViewRepresentable {
    let expression: String
    let range: Double   // ± domain extent in x and y

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = UIColor.secondarySystemBackground
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.antialiasingMode = .multisampling4X
        buildAndInstall(scene: scnView, expression: expression, range: Float(range),
                        coordinator: context.coordinator, resetCamera: true)
        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        let exprChanged  = context.coordinator.lastExpression != expression
        let rangeChanged = context.coordinator.lastRange      != range
        guard exprChanged || rangeChanged else { return }
        // Only snap camera back to default when the expression itself changes.
        buildAndInstall(scene: scnView, expression: expression, range: Float(range),
                        coordinator: context.coordinator, resetCamera: exprChanged)
    }

    // MARK: Scene (re)build

    private func buildAndInstall(scene scnView: SCNView, expression: String, range: Float,
                                  coordinator: Coordinator, resetCamera: Bool) {
        coordinator.lastExpression = expression
        coordinator.lastRange      = Double(range)

        // Save camera transform before wiping the scene (for range-only changes).
        let savedTransform = resetCamera ? nil : scnView.pointOfView?.transform

        let scene = SCNScene()
        addLights(to: scene)
        addSurface(to: scene, expression: expression, range: range)
        addAxes(to: scene, range: range)

        let camNode = SCNNode()
        camNode.camera = SCNCamera()
        // Position camera proportionally so the whole surface stays in frame.
        let d = range * 2.2
        camNode.position = SCNVector3(d, d * 0.75, d)
        camNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camNode)
        scnView.scene = scene
        scnView.pointOfView = camNode

        // Restore previous orbit angle when only range changed.
        if let t = savedTransform {
            scnView.pointOfView?.transform = t
        }
    }

    // MARK: Coordinator

    class Coordinator {
        var lastExpression: String = ""
        var lastRange: Double = -1   // -1 forces first build
    }

    // MARK: Lights

    private func addLights(to scene: SCNScene) {
        let ambient = SCNLight(); ambient.type = .ambient
        ambient.intensity = 350; ambient.color = UIColor.white
        let an = SCNNode(); an.light = ambient
        scene.rootNode.addChildNode(an)

        func dirLight(pos: SCNVector3, intensity: CGFloat) {
            let dl = SCNLight(); dl.type = .directional
            dl.intensity = intensity; dl.color = UIColor.white
            let dn = SCNNode(); dn.light = dl
            dn.position = pos; dn.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(dn)
        }
        dirLight(pos: SCNVector3( 8, 12,  6), intensity: 800)
        dirLight(pos: SCNVector3(-6, -4, -8), intensity: 300)
    }

    // MARK: Surface mesh

    private func addSurface(to scene: SCNScene, expression: String, range: Float) {
        let n = 60             // grid resolution per axis

        let step = range * 2 / Float(n)
        let stride = n + 1  // vertices per axis side

        // --- Step 1: compute all z values ---
        var zGrid = [[Float]](repeating: [Float](repeating: 0, count: stride), count: stride)
        var zMin: Float = .infinity, zMax: Float = -.infinity

        for i in 0...n {
            for j in 0...n {
                let xv = Double(-range + Float(i) * step)
                let yv = Double(-range + Float(j) * step)
                let zv = MathEvaluator.evaluate(expression, x: xv, y: yv) ?? 0
                let safe = zv.isFinite ? Float(zv) : 0
                zGrid[i][j] = safe
                if safe < zMin { zMin = safe }
                if safe > zMax { zMax = safe }
            }
        }
        let zRange = max(zMax - zMin, 0.001)

        // --- Step 2: build vertex list (SceneKit Y-up: math z → SCN y) ---
        var vertices  = [SCNVector3]()
        var normals   = [SCNVector3]()
        var uvCoords  = [CGPoint]()
        vertices.reserveCapacity(stride * stride)
        normals.reserveCapacity(stride * stride)
        uvCoords.reserveCapacity(stride * stride)

        for i in 0...n {
            for j in 0...n {
                let xv = -range + Float(i) * step
                let yv = -range + Float(j) * step
                let zv = zGrid[i][j]
                vertices.append(SCNVector3(xv, zv, yv))   // SCN: (x, height, depth)

                let t = (zv - zMin) / zRange
                uvCoords.append(CGPoint(x: 0.5, y: CGFloat(t)))
                normals.append(SCNVector3(0, 1, 0))
            }
        }

        // --- Step 3: smooth normals via finite differences ---
        for i in 0...n {
            for j in 0...n {
                let idx = i * stride + j
                let v = vertices[idx]

                let dx: SCNVector3
                if i < n {
                    let a = vertices[(i + 1) * stride + j]
                    dx = SCNVector3(a.x - v.x, a.y - v.y, a.z - v.z)
                } else {
                    let a = vertices[(i - 1) * stride + j]
                    dx = SCNVector3(v.x - a.x, v.y - a.y, v.z - a.z)
                }

                let dy: SCNVector3
                if j < n {
                    let a = vertices[i * stride + j + 1]
                    dy = SCNVector3(a.x - v.x, a.y - v.y, a.z - v.z)
                } else {
                    let a = vertices[i * stride + j - 1]
                    dy = SCNVector3(v.x - a.x, v.y - a.y, v.z - a.z)
                }

                let nx = dx.y * dy.z - dx.z * dy.y
                let ny = dx.z * dy.x - dx.x * dy.z
                let nz = dx.x * dy.y - dx.y * dy.x
                let len = sqrt(nx * nx + ny * ny + nz * nz)
                normals[idx] = len > 0
                    ? SCNVector3(nx / len, ny / len, nz / len)
                    : SCNVector3(0, 1, 0)
            }
        }

        // --- Step 4: build triangle index list ---
        var indices = [Int32]()
        indices.reserveCapacity(n * n * 6)
        for i in 0..<n {
            for j in 0..<n {
                let tl = Int32(i * stride + j)
                let tr = Int32(i * stride + j + 1)
                let bl = Int32((i + 1) * stride + j)
                let br = Int32((i + 1) * stride + j + 1)
                indices.append(contentsOf: [tl, bl, tr, tr, bl, br])
            }
        }

        // --- Step 5: build geometry ---
        let vertexSrc  = SCNGeometrySource(vertices: vertices)
        let normalSrc  = SCNGeometrySource(normals: normals)
        let uvSrc      = SCNGeometrySource(textureCoordinates: uvCoords)
        let indexData  = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element    = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<Int32>.size
        )

        let geometry = SCNGeometry(sources: [vertexSrc, normalSrc, uvSrc], elements: [element])
        geometry.firstMaterial?.diffuse.contents  = makeGradientTexture()
        geometry.firstMaterial?.specular.contents = UIColor.white
        geometry.firstMaterial?.shininess         = 50
        geometry.firstMaterial?.isDoubleSided     = true
        geometry.firstMaterial?.lightingModel     = .phong

        // Start flat against the XZ plane, then grow upward over 0.75 s.
        let surfaceNode = SCNNode(geometry: geometry)
        surfaceNode.scale = SCNVector3(1, 0.001, 1)
        scene.rootNode.addChildNode(surfaceNode)

        let grow = SCNAction.customAction(duration: 0.75) { node, elapsed in
            let t = Float(min(elapsed / 0.75, 1.0))
            let eased = t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t  // ease-in-out quad
            node.scale = SCNVector3(1, max(0.001, eased), 1)
        }
        surfaceNode.runAction(grow)
    }

    // MARK: Gradient texture

    private func makeGradientTexture() -> UIImage {
        let size = CGSize(width: 4, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors: [CGColor] = [
                UIColor.systemPurple.cgColor,
                UIColor.systemBlue.cgColor,
                UIColor.systemCyan.cgColor,
                UIColor.systemGreen.cgColor,
                UIColor.systemYellow.cgColor,
                UIColor.systemOrange.cgColor,
                UIColor.systemRed.cgColor,
            ]
            let locations: [CGFloat] = [0, 0.17, 0.33, 0.5, 0.67, 0.83, 1.0]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: locations
            ) else { return }
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
        }
    }

    // MARK: Coordinate axes

    private func addAxes(to scene: SCNScene, range: Float) {
        // Axes extend just beyond the plotted surface edge.
        let len = range + range * 0.15
        // Cylinder radius and sphere size scale with range so they stay visible.
        let r = CGFloat(range) * 0.012
        let tip = len + Float(r) * 2

        addAxisCylinder(to: scene, color: .systemRed, length: len, radius: r,
                        position: SCNVector3(len / 2, 0, 0),
                        rotation: SCNVector4(0, 0, 1, Float.pi / 2))
        addAxisCylinder(to: scene, color: .systemGreen, length: len, radius: r,
                        position: SCNVector3(0, 0, len / 2),
                        rotation: SCNVector4(1, 0, 0, Float.pi / 2))
        addAxisCylinder(to: scene, color: .systemBlue, length: len, radius: r,
                        position: SCNVector3(0, len / 2, 0),
                        rotation: SCNVector4(0, 1, 0, 0))

        addAxisSphere(to: scene, color: .systemRed,   at: SCNVector3(tip, 0, 0),   radius: r * 2)
        addAxisSphere(to: scene, color: .systemGreen, at: SCNVector3(0, 0, tip),   radius: r * 2)
        addAxisSphere(to: scene, color: .systemBlue,  at: SCNVector3(0, tip, 0),   radius: r * 2)
    }

    private func addAxisCylinder(to scene: SCNScene, color: UIColor, length: Float,
                                  radius: CGFloat, position: SCNVector3, rotation: SCNVector4) {
        let cyl = SCNCylinder(radius: radius, height: CGFloat(length))
        cyl.firstMaterial?.diffuse.contents = color
        cyl.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: cyl)
        node.position = position
        node.rotation = rotation
        scene.rootNode.addChildNode(node)
    }

    private func addAxisSphere(to scene: SCNScene, color: UIColor, at pos: SCNVector3, radius: CGFloat) {
        let sphere = SCNSphere(radius: radius)
        sphere.firstMaterial?.diffuse.contents = color
        sphere.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: sphere)
        node.position = pos
        scene.rootNode.addChildNode(node)
    }
}
#endif
