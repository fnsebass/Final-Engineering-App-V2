//
//  FBDEditorView.swift
//  Tolerance
//
//  Free Body Diagram editor.
//  • ZStack canvas (no SwiftUI Canvas-based Text — avoids known iOS crash)
//  • Physics simulation: object follows net force, bounces off walls, slides on ramps
//  • Ramps: right-triangle shape, auto normal-force display, weight decomposition
//  • Color picker: long-press any force arrow tip to change its color
//  • Recenter button resets object to canvas centre and stops simulation
//

#if os(iOS)
import SwiftUI
import SwiftData

// MARK: - Color helpers (iOS only)

private extension Color {
    init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        self.init(.sRGB,
                  red:   Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >>  8) & 0xFF) / 255,
                  blue:  Double( v        & 0xFF) / 255)
    }
    func hexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}

// MARK: - CGPoint helpers for ramp geometry (iOS only)

private extension FBDRamp {
    var startPt: CGPoint { CGPoint(x: x, y: y) }
    var endPt:   CGPoint { CGPoint(x: x + length * cos(angle * .pi/180),
                                   y: y - length * sin(angle * .pi/180)) }
    var midPt:   CGPoint { CGPoint(x: x + length/2 * cos(angle * .pi/180),
                                   y: y - length/2 * sin(angle * .pi/180)) }
    var normal:  CGPoint { CGPoint(x: normalDX, y: normalDY) }
}

// MARK: - FBDEditorView

struct FBDEditorView: View {
    @Bindable var diagram: FBDDiagram
    var onBack: () -> Void = {}

    // Persistent data
    @State private var forces: [FBDForce] = []
    @State private var ramps:  [FBDRamp]  = []

    // Object physics state
    @State private var objectPos:      CGPoint = CGPoint(x: 350, y: 240)
    @State private var objectVelocity: CGPoint = .zero
    @State private var isSimulating    = false
    @State private var onRamp:         FBDRamp? = nil
    @State private var canvasSize:     CGSize   = CGSize(width: 700, height: 480)

    // Interaction state
    @State private var selectedID:  UUID? = nil
    @State private var eraseMode          = false
    @State private var rampAddMode        = false

    // Add force sheet
    @State private var showAdd   = false
    @State private var addType:  FBDForceType = .applied
    @State private var addLabel  = ""
    @State private var addMag    = "10"
    @State private var addAngle  = "0"

    // Edit force sheet
    @State private var showEdit  = false
    @State private var editID:   UUID? = nil
    @State private var editMag   = ""
    @State private var editAngle = ""

    // Ramp sheet
    @State private var showRampSheet     = false
    @State private var pendingRampX      = 200.0
    @State private var pendingRampAngle  = 30.0
    @State private var pendingRampLen    = 240.0

    // Color picker
    @State private var colorForceID:    UUID?  = nil
    @State private var pickerColor:     Color  = .blue
    @State private var showColorPicker  = false

    // Analysis
    @State private var showAnalysis = false
    @State private var analysisText = ""

    // Arrow scale
    private let pixPerN: CGFloat  = 7.0
    private let maxArrowLen: CGFloat = 160
    private let bodyW: CGFloat    = 82
    private let bodyH: CGFloat    = 52

    // MARK: body

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            physicsCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            forces = diagram.loadForces()
            ramps  = diagram.loadRamps()
            let sx = diagram.objectX ?? 0, sy = diagram.objectY ?? 0
            if sx > 0 { objectPos = CGPoint(x: sx, y: sy) }
        }
        .onDisappear { isSimulating = false }
        .task(id: isSimulating) {
            guard isSimulating else { return }
            while isSimulating && !Task.isCancelled {
                updatePhysics()
                try? await Task.sleep(nanoseconds: 33_333_333)
            }
        }
        .sheet(isPresented: $showAdd)        { addSheet }
        .sheet(isPresented: $showEdit)       { editSheet }
        .sheet(isPresented: $showRampSheet)  { rampSheet }
        .sheet(isPresented: $showAnalysis)   { analysisSheet }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }.buttonStyle(.plain)

                Text(diagram.title)
                    .font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: 100)

                vDiv

                tBtn("eraser", active: eraseMode) {
                    eraseMode.toggle(); if eraseMode { isSimulating = false; selectedID = nil }
                }

                vDiv

                // Force type buttons
                ForEach(FBDForceType.allCases, id: \.self) { t in
                    Button {
                        eraseMode = false
                        addType = t; addLabel = t.rawValue
                        addAngle = String(Int(t.defaultAngle)); addMag = "10"
                        showAdd = true
                    } label: {
                        Image(systemName: t.sfIcon)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: t.defaultHex) ?? .blue)
                            .frame(width: 30, height: 30)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                }

                vDiv

                // Add ramp
                tBtn("triangle.fill", active: rampAddMode, color: .brown) { rampAddMode.toggle() }

                vDiv

                // Animate / Stop
                Button {
                    if isSimulating { stopSim() } else { startSim() }
                } label: {
                    Label(isSimulating ? "Stop" : "Animate",
                          systemImage: isSimulating ? "stop.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSimulating ? Color.red : Color.green)
                        .padding(.horizontal, 8).frame(height: 26)
                        .background((isSimulating ? Color.red : Color.green).opacity(0.12), in: Capsule())
                }.buttonStyle(.plain)

                // Recenter
                Button {
                    stopSim()
                    objectPos = CGPoint(x: canvasSize.width/2, y: canvasSize.height/2)
                    objectVelocity = .zero; onRamp = nil
                    diagram.objectX = Double(objectPos.x); diagram.objectY = Double(objectPos.y)
                } label: {
                    Image(systemName: "scope")
                        .frame(width: 30, height: 30)
                        .foregroundStyle(Color.secondary)
                }.buttonStyle(.plain)

                vDiv

                // Delete selected force
                Button {
                    if let id = selectedID {
                        forces.removeAll { $0.id == id }; selectedID = nil; saveForces()
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(selectedID != nil ? Color.red : Color.secondary)
                        .frame(width: 30, height: 30)
                }.buttonStyle(.plain).disabled(selectedID == nil)

                vDiv

                Button { buildAnalysis(); showAnalysis = true } label: {
                    Label("Analyze", systemImage: "function")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.purple)
                        .padding(.horizontal, 8).frame(height: 26)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                }.buttonStyle(.plain).padding(.trailing, 6)
            }
            .frame(height: 36)
            .padding(.leading, 2)
        }
        .background(.bar)
    }

    private func tBtn(_ icon: String, active: Bool, color: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? color : Color.secondary)
                .frame(width: 28, height: 28)
                .background(active ? color.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }

    private var vDiv: some View {
        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 20).padding(.horizontal, 3)
    }

    // MARK: - Physics canvas

    private var clampedPos: CGPoint {
        CGPoint(
            x: min(max(objectPos.x, bodyW/2), max(bodyW/2, canvasSize.width  - bodyW/2)),
            y: min(max(objectPos.y, bodyH/2), max(bodyH/2, canvasSize.height - bodyH/2))
        )
    }

    private var physicsCanvas: some View {
        ZStack {
            // ── Layer 1: background (handles background taps) ──────────────
            Color(red: 0.97, green: 0.97, blue: 0.98)
                .onTapGesture(coordinateSpace: .local) { pt in
                    if rampAddMode { openRampSheet(at: pt) }
                    else           { selectedID = nil }
                }

            // ── Layer 2: Canvas (geometric drawing only — NO text) ─────────
            Canvas { ctx, _ in
                drawRamps(ctx)
                drawForceArrows(ctx, at: clampedPos)
                if let r = onRamp { drawDecomposition(ctx, ramp: r, at: clampedPos) }
                drawBodyShadow(ctx, at: clampedPos)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

            // ── Layer 3: Object body ─────────────────────────────────────
            objectBodyView

            // ── Layer 4: Force labels (SwiftUI Text — never crashes) ──────
            ForEach(forces) { force in
                let tip = tipOf(force, from: clampedPos)
                let col = Color(hex: force.resolvedColorHex) ?? .blue
                let dx  = CGFloat(cos(force.angle * .pi / 180))
                let dy  = -CGFloat(sin(force.angle * .pi / 180))
                Text("\(force.label) \(fmtN(force.magnitude))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(col)
                    .shadow(color: .white, radius: 2)
                    .position(x: tip.x + dx * 22, y: tip.y + dy * 22)
                    .allowsHitTesting(false)
            }

            // Auto-normal and decomp labels when on ramp
            rampLabels

            // ── Layer 5: Force tap / long-press hit targets ────────────────
            ForEach(forces) { force in
                Color.clear
                    .frame(width: 50, height: 50)
                    .contentShape(Rectangle())
                    .position(tipOf(force, from: clampedPos))
                    .onTapGesture {
                        if eraseMode {
                            forces.removeAll { $0.id == force.id }
                            if selectedID == force.id { selectedID = nil }
                            saveForces()
                        } else if selectedID == force.id {
                            startEdit(force)
                        } else {
                            selectedID = force.id
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.45) {
                        colorForceID = force.id
                        pickerColor  = Color(hex: force.resolvedColorHex) ?? .blue
                        showColorPicker = true
                    }
            }

            // Ramp erase targets
            ForEach(ramps) { ramp in
                Color.clear
                    .frame(width: 54, height: 54)
                    .contentShape(Rectangle())
                    .position(ramp.midPt)
                    .onTapGesture {
                        guard eraseMode else { return }
                        ramps.removeAll { $0.id == ramp.id }
                        if onRamp?.id == ramp.id { onRamp = nil }
                        saveRamps()
                    }
            }

            // ── Layer 6: Color picker modal (avoids sheet/freeze issues) ───
            if showColorPicker { colorPickerOverlay }

            // Mode hints
            if eraseMode || rampAddMode {
                Text(rampAddMode ? "Tap to place ramp" : "Tap a force or ramp to erase")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(12).allowsHitTesting(false)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
    }

    // MARK: - Object body view

    private var objectBodyView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray5))
            RoundedRectangle(cornerRadius: 8)
                .stroke(selectedID == nil ? Color(.systemGray3) : Color.accentColor,
                        lineWidth: selectedID == nil ? 1.5 : 2.5)
            Text("m").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(.systemGray))
        }
        .frame(width: bodyW, height: bodyH)
        .position(clampedPos)
        .gesture(DragGesture()
            .onChanged { v in
                guard !isSimulating else { return }
                objectPos = v.location
            }
            .onEnded { v in
                objectPos = v.location; objectVelocity = .zero
                diagram.objectX = Double(objectPos.x); diagram.objectY = Double(objectPos.y)
            }
        )
    }

    // MARK: - Ramp auto-labels

    @ViewBuilder
    private var rampLabels: some View {
        if let ramp = onRamp, let wf = weightForce {
            let N    = wf.magnitude * cos(ramp.angle * .pi / 180)
            let Wpar = wf.magnitude * sin(ramp.angle * .pi / 180)
            let n    = ramp.normal
            let base = clampedPos
            let nScale = min(CGFloat(N) * 3, maxArrowLen * 0.65)
            let rampDx = -CGFloat(cos(ramp.angle * .pi / 180))
            let rampDy =  CGFloat(sin(ramp.angle * .pi / 180))
            let pScale = min(CGFloat(Wpar) * 3, maxArrowLen * 0.65)

            Text("N = \(fmtN(N)) N")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
                .shadow(color: .white, radius: 2)
                .position(x: base.x + n.x * (nScale + 20),
                          y: base.y + n.y * (nScale + 20))
                .allowsHitTesting(false)

            Text("W∥ = \(fmtN(Wpar)) N")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)
                .shadow(color: .white, radius: 2)
                .position(x: base.x + rampDx * (pScale + 20),
                          y: base.y + rampDy * (pScale + 20))
                .allowsHitTesting(false)
        }
    }

    private var weightForce: FBDForce? { forces.first { $0.type == .weight } }

    // MARK: - Canvas draw functions (geometry only — no text)

    private func drawRamps(_ ctx: GraphicsContext) {
        for ramp in ramps {
            let s = ramp.startPt, e = ramp.endPt
            let base = CGPoint(x: e.x, y: s.y)
            var tri = Path()
            tri.move(to: s); tri.addLine(to: e); tri.addLine(to: base); tri.closeSubpath()
            ctx.fill(tri, with: .color(Color(.systemGray3)))
            ctx.stroke(tri, with: .color(Color(.systemGray)), lineWidth: 1.5)
        }
    }

    private func drawForceArrows(_ ctx: GraphicsContext, at pos: CGPoint) {
        for force in forces {
            let col = Color(hex: force.resolvedColorHex) ?? .blue
            let lw: CGFloat = force.id == selectedID ? 3.0 : 2.0
            let tip = tipOf(force, from: pos)

            var shaft = Path()
            shaft.move(to: pos); shaft.addLine(to: tip)
            ctx.stroke(shaft, with: .color(col), style: StrokeStyle(lineWidth: lw, lineCap: .round))

            let rad = force.angle * .pi / 180
            let sdx = CGFloat(cos(rad)), sdy = -CGFloat(sin(rad))
            let bx = -sdx, by = -sdy
            let c = CGFloat(cos(0.45)), s = CGFloat(sin(0.45))
            let hl: CGFloat = 12
            var head = Path()
            head.move(to: tip)
            head.addLine(to: CGPoint(x: tip.x + hl*(bx*c - by*s), y: tip.y + hl*(bx*s + by*c)))
            head.move(to: tip)
            head.addLine(to: CGPoint(x: tip.x + hl*(bx*c + by*s), y: tip.y + hl*(-bx*s + by*c)))
            ctx.stroke(head, with: .color(col), style: StrokeStyle(lineWidth: lw, lineCap: .round))

            if force.id == selectedID {
                ctx.fill(Path(ellipseIn: CGRect(x: tip.x-8, y: tip.y-8, width: 16, height: 16)),
                         with: .color(col.opacity(0.22)))
            }
        }
    }

    private func drawDecomposition(_ ctx: GraphicsContext, ramp: FBDRamp, at pos: CGPoint) {
        guard let wf = weightForce else { return }
        let W = CGFloat(wf.magnitude)
        let θ = ramp.angle * .pi / 180

        // Down-slope arrow (orange dashed)
        let Wpar = W * sin(θ)
        let rampDx = -CGFloat(cos(θ)), rampDy = CGFloat(sin(θ))
        let pScale = min(Wpar * 3, maxArrowLen * 0.62)
        let pTip = CGPoint(x: pos.x + rampDx * pScale, y: pos.y + rampDy * pScale)
        var pPath = Path(); pPath.move(to: pos); pPath.addLine(to: pTip)
        ctx.stroke(pPath, with: .color(Color.orange.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 1.8, dash: [5, 3]))
        drawSmallHead(ctx, tip: pTip, dx: rampDx, dy: rampDy, col: Color.orange.opacity(0.85))

        // Normal-force arrow (green dashed)
        let N = W * cos(θ)
        let n = ramp.normal
        let nScale = min(N * 3, maxArrowLen * 0.62)
        let nTip = CGPoint(x: pos.x + n.x * nScale, y: pos.y + n.y * nScale)
        var nPath = Path(); nPath.move(to: pos); nPath.addLine(to: nTip)
        ctx.stroke(nPath, with: .color(Color.green.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 1.8, dash: [5, 3]))
        drawSmallHead(ctx, tip: nTip, dx: n.x, dy: n.y, col: Color.green.opacity(0.85))
    }

    private func drawSmallHead(_ ctx: GraphicsContext, tip: CGPoint,
                                dx: CGFloat, dy: CGFloat, col: Color) {
        let bx = -dx, by = -dy
        let c = CGFloat(cos(0.45)), s = CGFloat(sin(0.45))
        let hl: CGFloat = 8
        var h = Path()
        h.move(to: tip)
        h.addLine(to: CGPoint(x: tip.x + hl*(bx*c - by*s), y: tip.y + hl*(bx*s + by*c)))
        h.move(to: tip)
        h.addLine(to: CGPoint(x: tip.x + hl*(bx*c + by*s), y: tip.y + hl*(-bx*s + by*c)))
        ctx.stroke(h, with: .color(col), lineWidth: 1.8)
    }

    private func drawBodyShadow(_ ctx: GraphicsContext, at pos: CGPoint) {
        let r = CGRect(x: pos.x - bodyW/2 + 2, y: pos.y - bodyH/2 + 3, width: bodyW, height: bodyH)
        ctx.fill(Path(roundedRect: r, cornerRadius: 8), with: .color(Color.black.opacity(0.07)))
    }

    // MARK: - Color picker overlay

    private var colorPickerOverlay: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
                .onTapGesture { showColorPicker = false }
            VStack(spacing: 14) {
                Text("Arrow Color").font(.headline)
                ColorPicker("", selection: $pickerColor, supportsOpacity: false)
                    .labelsHidden().frame(width: 200)
                HStack(spacing: 20) {
                    Button("Cancel") { showColorPicker = false }.foregroundStyle(.secondary)
                    Button("Apply")  { applyColor() }.bold()
                }
            }
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .shadow(radius: 14)
        }
    }

    private func applyColor() {
        guard let id = colorForceID,
              let idx = forces.firstIndex(where: { $0.id == id }) else {
            showColorPicker = false; return
        }
        forces[idx].colorHex = pickerColor.hexString()
        saveForces(); showColorPicker = false
    }

    // MARK: - Add force sheet

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Force Type") {
                    Picker("Type", selection: $addType) {
                        ForEach(FBDForceType.allCases, id: \.self) { t in
                            Label(t.rawValue, systemImage: t.sfIcon).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: addType) { _, t in
                        if FBDForceType.allCases.map(\.rawValue).contains(addLabel) { addLabel = t.rawValue }
                        addAngle = String(Int(t.defaultAngle))
                    }
                }
                Section("Properties") {
                    HStack { Text("Label"); Spacer()
                        TextField("F₁", text: $addLabel).multilineTextAlignment(.trailing)
                    }
                    HStack { Text("Magnitude"); Spacer()
                        TextField("N", text: $addMag).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).frame(width: 80)
                        Text("N").foregroundStyle(.secondary)
                    }
                    HStack { Text("Angle"); Spacer()
                        TextField("°", text: $addAngle).keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing).frame(width: 80)
                        Text("°").foregroundStyle(.secondary)
                    }
                    Text("0° = right  90° = up  180° = left  270° = down")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add \(addType.rawValue) Force")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAdd = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { commitAdd() }.disabled((Double(addMag) ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.height(380)])
    }

    private func commitAdd() {
        guard let mag = Double(addMag), mag > 0, let ang = Double(addAngle) else { return }
        let f = FBDForce(label: addLabel.isEmpty ? addType.rawValue : addLabel,
                         magnitude: mag, angle: ang, type: addType)
        forces.append(f); selectedID = f.id; saveForces(); showAdd = false
    }

    // MARK: - Edit force sheet

    @ViewBuilder
    private var editSheet: some View {
        if let id = editID, let idx = forces.firstIndex(where: { $0.id == id }) {
            NavigationStack {
                Form {
                    Section("Magnitude (N)") { TextField("N", text: $editMag).keyboardType(.decimalPad) }
                    Section("Angle (°)") {
                        TextField("°", text: $editAngle).keyboardType(.numbersAndPunctuation)
                        Text("0° = right  90° = up  180° = left  270° = down").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Edit \(forces[idx].label)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showEdit = false; editID = nil } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { commitEdit(idx: idx) } }
                }
            }
            .presentationDetents([.height(280)])
        }
    }

    private func startEdit(_ f: FBDForce) {
        editID = f.id; editMag = String(format: "%.4g", f.magnitude)
        editAngle = String(format: "%.1f", f.angle); showEdit = true
    }

    private func commitEdit(idx: Int) {
        if let m = Double(editMag),  m > 0 { forces[idx].magnitude = m }
        if let a = Double(editAngle)        { forces[idx].angle = a }
        saveForces(); showEdit = false; editID = nil
    }

    // MARK: - Ramp sheet

    private var rampSheet: some View {
        NavigationStack {
            Form {
                Section("Ramp Angle") {
                    VStack(alignment: .leading, spacing: 6) {
                        Slider(value: $pendingRampAngle, in: 5...70)
                        Text("\(Int(pendingRampAngle))° from horizontal")
                            .font(.headline).frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                Section("Length") {
                    Slider(value: $pendingRampLen, in: 120...400)
                    Text("\(Int(pendingRampLen)) px").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Configure Ramp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRampSheet = false; rampAddMode = false }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { commitRamp() } }
            }
        }
        .presentationDetents([.height(300)])
    }

    private func openRampSheet(at pt: CGPoint) {
        pendingRampX = Double(pt.x); pendingRampAngle = 30; pendingRampLen = 240
        showRampSheet = true
    }

    private func commitRamp() {
        let rampY = canvasSize.height * 0.68
        let halfW = pendingRampLen / 2 * cos(pendingRampAngle * .pi / 180)
        let r = FBDRamp(x: pendingRampX - halfW, y: rampY,
                        angle: pendingRampAngle, length: pendingRampLen)
        ramps.append(r); saveRamps(); showRampSheet = false; rampAddMode = false
    }

    // MARK: - Analysis sheet

    private var analysisSheet: some View {
        NavigationStack {
            ScrollView {
                Text(analysisText.isEmpty ? "Add forces first." : analysisText)
                    .font(.system(size: 14).monospaced())
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Equilibrium Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAnalysis = false } } }
        }
        .presentationDetents([.large])
    }

    private func buildAnalysis() {
        guard !forces.isEmpty else { analysisText = "No forces added yet."; return }
        var lines = ["FORCES:"]
        for f in forces {
            lines.append("  \(f.label) = \(String(format: "%.2g", f.magnitude)) N @ \(String(format: "%.1f", f.angle))°")
            lines.append("    Fx = \(String(format: "%.3f", f.fx)) N   Fy = \(String(format: "%.3f", f.fy)) N")
        }
        let ΣFx = forces.reduce(0.0) { $0 + $1.fx }
        let ΣFy = forces.reduce(0.0) { $0 + $1.fy }
        if let ramp = onRamp, let wf = weightForce {
            let N = wf.magnitude * cos(ramp.angle * .pi / 180)
            let Wp = wf.magnitude * sin(ramp.angle * .pi / 180)
            lines += ["", "ON RAMP (θ = \(String(format: "%.1f", ramp.angle))°):",
                      "  Normal force N = \(String(format: "%.3f", N)) N",
                      "  Down-slope W∥  = \(String(format: "%.3f", Wp)) N"]
        }
        let eq = abs(ΣFx) < 0.01 && abs(ΣFy) < 0.01
        lines += ["", "RESULT:",
                  "  ΣFx = \(String(format: "%.4f", ΣFx)) N",
                  "  ΣFy = \(String(format: "%.4f", ΣFy)) N", "",
                  eq ? "✓  Translational equilibrium." : "✗  NOT in equilibrium.\n   Net = (\(String(format: "%.3f", ΣFx)), \(String(format: "%.3f", ΣFy))) N"]
        analysisText = lines.joined(separator: "\n")
    }

    // MARK: - Physics

    private func startSim() { isSimulating = true; objectVelocity = .zero }
    private func stopSim()  { isSimulating = false; objectVelocity = .zero }

    private func updatePhysics() {
        let dt:     CGFloat = 1.0 / 30.0
        let scale:  CGFloat = 9.0      // px/s² per Newton
        let damp:   CGFloat = 0.92

        // Net force in screen coords (+x right, +y down)
        var nx: CGFloat = 0, ny: CGFloat = 0
        for f in forces {
            let rad = f.angle * .pi / 180
            nx += CGFloat(f.magnitude) *  cos(rad)
            ny += CGFloat(f.magnitude) * -sin(rad)  // flip y for screen
        }

        // Ramp collision
        var hitRamp: FBDRamp? = nil
        for ramp in ramps {
            if let sy = ramp.surfaceY(at: Double(objectPos.x)) {
                let bottomY = Double(objectPos.y + bodyH / 2)
                if bottomY >= sy - 10 && bottomY <= sy + 30 {
                    hitRamp = ramp
                    objectPos.y = CGFloat(sy) - bodyH / 2

                    let n = ramp.normal
                    // Remove force component INTO ramp
                    let dotF = nx * n.x + ny * n.y
                    if dotF < 0 { nx -= dotF * n.x; ny -= dotF * n.y }
                    // Remove velocity component INTO ramp
                    let dotV = objectVelocity.x * n.x + objectVelocity.y * n.y
                    if dotV < 0 { objectVelocity.x -= dotV * n.x; objectVelocity.y -= dotV * n.y }
                    break
                }
            }
        }
        onRamp = hitRamp

        // Integrate velocity & position
        objectVelocity.x = (objectVelocity.x + nx * scale * dt) * damp
        objectVelocity.y = (objectVelocity.y + ny * scale * dt) * damp
        objectPos.x += objectVelocity.x * dt * 60
        objectPos.y += objectVelocity.y * dt * 60

        // Boundary bounce
        let hw = bodyW/2, hh = bodyH/2
        let cw = canvasSize.width, ch = canvasSize.height
        if objectPos.x < hw  { objectPos.x = hw;    objectVelocity.x =  abs(objectVelocity.x) * 0.3 }
        if objectPos.x > cw - hw { objectPos.x = cw - hw; objectVelocity.x = -abs(objectVelocity.x) * 0.3 }
        if objectPos.y < hh  { objectPos.y = hh;    objectVelocity.y =  abs(objectVelocity.y) * 0.3 }
        if objectPos.y > ch - hh { objectPos.y = ch - hh; objectVelocity.y = 0; objectVelocity.x *= 0.82 }
    }

    // MARK: - Helpers

    private func tipOf(_ force: FBDForce, from pos: CGPoint) -> CGPoint {
        let len = min(max(30, CGFloat(force.magnitude) * pixPerN), maxArrowLen)
        let rad = force.angle * .pi / 180
        return CGPoint(x: pos.x + len * cos(rad), y: pos.y - len * sin(rad))
    }

    private func fmtN(_ v: Double) -> String {
        v < 1000 ? String(format: "%.4g", v) : String(format: "%.3g", v)
    }

    private func saveForces() { diagram.save(forces: forces) }
    private func saveRamps()  { diagram.save(ramps: ramps) }
}
#endif
