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
    @Binding var isPresented: Bool

    @State private var editExpr: String
    @FocusState private var fieldFocused: Bool

    // 2-D state
    @State private var xMin: Double = -10
    @State private var xMax: Double = 10
    @State private var graphHeight: CGFloat = 300

    // 3-D state — domain ±range in both x and y
    @State private var axisRange: Double = 5

    // 2-D draw-in animation (0 = hidden, 1 = fully revealed)
    @State private var chartReveal: CGFloat = 0

    init(equationText: String, expression: String, isPresented: Binding<Bool>) {
        self.equationText = equationText
        self.expression = expression
        self._isPresented = isPresented
        self._editExpr = State(initialValue: expression)
    }

    private var is3D: Bool { MathEvaluator.is3DExpression(editExpr) }

    var body: some View {
        VStack(spacing: 0) {
            header
            expressionRow
            Divider()
            if editExpr.trimmingCharacters(in: .whitespaces).isEmpty {
                emptyPrompt
            } else if is3D {
                Graph3DScene(expression: editExpr, range: axisRange)
                    .frame(height: 360)
                Divider()
                controls3D
                hint3D
            } else {
                chartArea
                Divider()
                controls2D
            }
        }
        .frame(height: is3D ? nil : (editExpr.isEmpty ? 220 : graphHeight))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.blue.opacity(0.35), lineWidth: 1))
        .shadow(radius: 18, y: 6)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: is3D ? "cube" : "waveform.path.ecg")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(is3D ? "3-D Graph" : "Graph")
                    .font(.subheadline.weight(.semibold))
                Text(equationText.isEmpty ? "Edit the expression below" : equationText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3)) { isPresented = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Expression editor row

    private var expressionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "function")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 16)
            TextField("e.g. cos(sqrt(x^2+y^2))", text: $editExpr)
                .font(.system(.caption, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($fieldFocused)
                .onSubmit { fieldFocused = false }
            // Reset button — only visible when user has drifted from OCR suggestion
            if !editExpr.isEmpty && editExpr != expression {
                Button {
                    editExpr = expression
                    fieldFocused = false
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

    private var plotData: [DataPoint] {
        guard xMax > xMin, !editExpr.isEmpty else { return [] }
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
        return pts
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
