//
//  ShearBendingView.swift
//  Tolerance
//
//  Shear Force & Bending Moment Diagram editor.
//  All text labels are SwiftUI Text views (never inside Canvas) to avoid iOS Canvas-Text crashes.
//

#if os(iOS)
import SwiftUI
import SwiftData

private enum BeamAddMode: Equatable {
    case none
    case support(SupportType)
    case load(BeamLoadType)
    case erase
}

struct ShearBendingView: View {
    @Bindable var diagram: BeamDiagram
    var onBack: () -> Void = {}

    @State private var supports: [BeamSupport] = []
    @State private var loads:    [BeamLoad]    = []
    @State private var mode:     BeamAddMode   = .none

    @State private var pendingPosition: Double = 0
    @State private var showAddSheet = false
    @State private var pendingMag   = "10"
    @State private var pendingEnd   = ""
    @State private var pendingType: BeamLoadType = .point

    @State private var showLengthSheet = false
    @State private var draftLength     = ""

    @State private var xs: [Double] = []
    @State private var vs: [Double] = []
    @State private var ms: [Double] = []
    @State private var ra: Double?  = nil
    @State private var rb: Double?  = nil
    @State private var solveError: String? = nil

    // Canvas geometry
    private let canvasW:   CGFloat = 820
    private let beamY:     CGFloat = 100
    private let paddingX:  CGFloat = 70

    private var usableW: CGFloat { canvasW - paddingX * 2 }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    beamSection
                    Divider().padding(.vertical, 2)
                    if !vs.isEmpty {
                        diagramSection(title: "Shear Force  (kN)", values: vs, color: .blue)
                        Divider().padding(.vertical, 2)
                        diagramSection(title: "Bending Moment  (kN·m)", values: ms, color: Color(red: 0.1, green: 0.65, blue: 0.3))
                    } else if let err = solveError {
                        Text(err).foregroundStyle(.red).font(.callout).padding(20)
                    } else {
                        Text("Press  Calculate  to generate diagrams.")
                            .foregroundStyle(.secondary).font(.callout).padding(20)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear { supports = diagram.loadSupports(); loads = diagram.loadLoads() }
        .sheet(isPresented: $showAddSheet) { addSheet }
        .sheet(isPresented: $showLengthSheet) { lengthSheet }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }.buttonStyle(.plain)

                Text(diagram.title).font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: 110)

                vDiv

                modeBtn("Pin",    "triangle",              .support(.pin))
                modeBtn("Roller", "triangle.circle",        .support(.roller))
                vDiv
                modeBtn("Point",  "arrow.down",             .load(.point))
                modeBtn("Dist.",  "arrow.down.to.line",     .load(.distributed))
                modeBtn("Moment", "arrow.clockwise",        .load(.moment))
                vDiv

                Button {
                    mode = mode == .erase ? .none : .erase
                } label: {
                    Image(systemName: "eraser")
                        .foregroundStyle(mode == .erase ? Color.red : Color.secondary)
                        .frame(width: 30, height: 30)
                        .background(mode == .erase ? Color.red.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)

                vDiv

                Button { showLengthSheet = true } label: {
                    Label("\(String(format: "%.1f", diagram.beamLength)) m", systemImage: "ruler")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).frame(height: 26)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)

                vDiv

                Button { calculate() } label: {
                    Label("Calculate", systemImage: "chart.xyaxis.line")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Color.accentColor, in: Capsule())
                }.buttonStyle(.plain).padding(.trailing, 6)
            }
            .frame(height: 36)
        }
        .background(.bar)
    }

    private func modeBtn(_ title: String, _ icon: String, _ m: BeamAddMode) -> some View {
        Button { mode = mode == m ? .none : m } label: {
            VStack(spacing: 1) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 9))
            }
            .foregroundStyle(mode == m ? Color.accentColor : Color.secondary)
            .frame(width: 42, height: 34)
            .background(mode == m ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }

    private var vDiv: some View {
        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 20).padding(.horizontal, 3)
    }

    // MARK: - Beam section (Canvas for geometry + overlay for labels)

    private func xToCanvas(_ pos: Double) -> CGFloat {
        paddingX + CGFloat(pos / diagram.beamLength) * usableW
    }
    private func canvasToX(_ cx: CGFloat) -> Double {
        Double((cx - paddingX) / usableW) * diagram.beamLength
    }

    private var beamSection: some View {
        ZStack(alignment: .topLeading) {
            // Subtle warm background
            LinearGradient(colors: [Color(.systemBackground), Color(.systemGray6)],
                           startPoint: .top, endPoint: .bottom)

            // Geometry-only canvas (NO text inside)
            Canvas { ctx, _ in
                drawBeamGeometry(ctx)
                for s in supports { drawSupportGeometry(ctx, s) }
                for l in loads    { drawLoadGeometry(ctx, l) }
                if let a = ra, let b = rb { drawReactionGeometry(ctx, ra: a, rb: b) }
            }
            .frame(width: canvasW, height: 200)
            .allowsHitTesting(false)

            // Text labels as SwiftUI views (safe — no Canvas-Text crash)
            beamTextLabels

            // Transparent tap layer
            Color.clear
                .frame(width: canvasW, height: 200)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { handleBeamTap(at: $0) }
        }
        .frame(width: canvasW, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Beam text labels (SwiftUI, not Canvas)

    private var beamTextLabels: some View {
        ZStack(alignment: .topLeading) {
            // Beam x-labels
            Text("0").font(.system(size: 11)).foregroundStyle(.secondary)
                .position(x: paddingX, y: beamY + 32)
            Text(String(format: "%.1f m", diagram.beamLength)).font(.system(size: 11)).foregroundStyle(.secondary)
                .position(x: xToCanvas(diagram.beamLength), y: beamY + 32)

            // Support position labels
            ForEach(supports) { s in
                let cx = xToCanvas(s.position)
                Text(String(format: "%.1f", s.position))
                    .font(.system(size: 9)).foregroundStyle(Color.secondary)
                    .position(x: cx, y: beamY + (s.type == .roller ? 72 : 58))
            }

            // Load labels
            ForEach(loads) { l in
                let cx = xToCanvas(l.position)
                let sign: CGFloat = l.magnitude >= 0 ? -1 : 1
                let label = loadLabel(l)
                Text(label).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(loadColor(l))
                    .position(x: cx + 28, y: beamY + sign * 38 + 10)
            }

            // Reaction labels
            if let a = ra, let b = rb {
                let sorted = supports.sorted { $0.position < $1.position }
                if sorted.count >= 2 {
                    let posA = xToCanvas(sorted[0].position), posB = xToCanvas(sorted[1].position)
                    Text("Rₐ=\(String(format: "%.2f", a)) kN")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Color.teal)
                        .position(x: posA + 36, y: beamY - 36)
                    Text("Rb=\(String(format: "%.2f", b)) kN")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Color.teal)
                        .position(x: posB + 36, y: beamY - 36)
                }
            }

            // Mode hint
            if mode != .none {
                Text(modeHint)
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(5).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .position(x: canvasW - 100, y: 14)
            }
        }
        .frame(width: canvasW, height: 200)
        .allowsHitTesting(false)
    }

    private func loadLabel(_ l: BeamLoad) -> String {
        switch l.type {
        case .point:       return "\(String(format: "%.4g", abs(l.magnitude))) kN"
        case .distributed: return "\(String(format: "%.4g", abs(l.magnitude))) kN/m"
        case .moment:      return "\(String(format: "%.4g", abs(l.magnitude))) kN·m"
        }
    }
    private func loadColor(_ l: BeamLoad) -> Color {
        switch l.type { case .point: return .red; case .distributed: return .orange; case .moment: return .purple }
    }

    private var modeHint: String {
        switch mode {
        case .none: return ""
        case .support(let t): return "Tap beam → add \(t.rawValue)"
        case .load(let t):    return "Tap beam → add \(t.rawValue)"
        case .erase:          return "Tap item to erase"
        }
    }

    // MARK: - Beam geometry drawing (NO text)

    private func drawBeamGeometry(_ ctx: GraphicsContext) {
        let x0 = xToCanvas(0), x1 = xToCanvas(diagram.beamLength)
        var beam = Path()
        beam.move(to: CGPoint(x: x0, y: beamY))
        beam.addLine(to: CGPoint(x: x1, y: beamY))
        ctx.stroke(beam, with: .color(Color(.label)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
    }

    private func drawSupportGeometry(_ ctx: GraphicsContext, _ s: BeamSupport) {
        let cx = xToCanvas(s.position), cy = beamY + 4
        let h: CGFloat = 22
        var tri = Path()
        tri.move(to: CGPoint(x: cx, y: cy))
        tri.addLine(to: CGPoint(x: cx - 13, y: cy + h))
        tri.addLine(to: CGPoint(x: cx + 13, y: cy + h))
        tri.closeSubpath()
        ctx.stroke(tri, with: .color(Color(.label)), lineWidth: 1.5)
        if s.type == .roller {
            ctx.stroke(Path(ellipseIn: CGRect(x: cx-5, y: cy+h, width: 10, height: 10)),
                       with: .color(Color(.label)), lineWidth: 1.5)
        }
    }

    private func drawLoadGeometry(_ ctx: GraphicsContext, _ l: BeamLoad) {
        let cx = xToCanvas(l.position)
        let sign: CGFloat = l.magnitude >= 0 ? -1 : 1
        switch l.type {
        case .point:
            let top = beamY + sign * 48
            var p = Path(); p.move(to: CGPoint(x: cx, y: top)); p.addLine(to: CGPoint(x: cx, y: beamY))
            ctx.stroke(p, with: .color(.red), lineWidth: 2)
            drawHead(ctx, at: CGPoint(x: cx, y: beamY), dx: 0, dy: sign > 0 ? 1 : -1, col: .red)
        case .distributed:
            let ex = xToCanvas(l.endPosition ?? (l.position + 1))
            let n = max(2, Int((ex - cx) / 18))
            for i in 0...n {
                let ax = cx + CGFloat(i) * (ex - cx) / CGFloat(n)
                var p = Path(); p.move(to: CGPoint(x: ax, y: beamY + sign * 38)); p.addLine(to: CGPoint(x: ax, y: beamY))
                ctx.stroke(p, with: .color(.orange), lineWidth: 1)
            }
            var top = Path()
            top.move(to: CGPoint(x: cx, y: beamY + sign * 38))
            top.addLine(to: CGPoint(x: ex, y: beamY + sign * 38))
            ctx.stroke(top, with: .color(.orange), lineWidth: 2)
        case .moment:
            let r: CGFloat = 16
            ctx.stroke(
                Path { p in p.addArc(center: CGPoint(x: cx, y: beamY), radius: r,
                                     startAngle: .degrees(0), endAngle: .degrees(270),
                                     clockwise: l.magnitude >= 0) },
                with: .color(.purple), lineWidth: 2)
        }
    }

    private func drawHead(_ ctx: GraphicsContext, at pt: CGPoint, dx: CGFloat, dy: CGFloat, col: Color) {
        let bx = -dx, by = -dy
        let c = CGFloat(cos(0.4)), s = CGFloat(sin(0.4))
        let hl: CGFloat = 10
        var h = Path()
        h.move(to: pt)
        h.addLine(to: CGPoint(x: pt.x + hl*(bx*c - by*s), y: pt.y + hl*(bx*s + by*c)))
        h.move(to: pt)
        h.addLine(to: CGPoint(x: pt.x + hl*(bx*c + by*s), y: pt.y + hl*(-bx*s + by*c)))
        ctx.stroke(h, with: .color(col), lineWidth: 2)
    }

    private func drawReactionGeometry(_ ctx: GraphicsContext, ra: Double, rb: Double) {
        let sorted = supports.sorted { $0.position < $1.position }
        guard sorted.count >= 2 else { return }
        func drawR(_ cx: CGFloat, _ val: Double) {
            let sign: CGFloat = val >= 0 ? -1 : 1
            let tail = CGPoint(x: cx, y: beamY - sign * 42)
            var s = Path(); s.move(to: tail); s.addLine(to: CGPoint(x: cx, y: beamY))
            ctx.stroke(s, with: .color(.teal), lineWidth: 2)
            drawHead(ctx, at: CGPoint(x: cx, y: beamY), dx: 0, dy: sign > 0 ? 1 : -1, col: .teal)
        }
        drawR(xToCanvas(sorted[0].position), ra)
        drawR(xToCanvas(sorted[1].position), rb)
    }

    // MARK: - Beam tap handling

    private func handleBeamTap(at loc: CGPoint) {
        let raw = canvasToX(loc.x)
        let clamped = max(0, min(raw, diagram.beamLength))
        switch mode {
        case .none: return
        case .erase: eraseNearestItem(at: loc)
        case .support(let t):
            supports.append(BeamSupport(position: clamped, type: t))
            diagram.save(supports: supports); invalidate()
        case .load(let t):
            pendingPosition = clamped; pendingType = t
            pendingMag = "10"
            pendingEnd = String(format: "%.1f", min(clamped + 2, diagram.beamLength))
            showAddSheet = true
        }
    }

    private func eraseNearestItem(at loc: CGPoint) {
        for (i, l) in loads.enumerated() {
            if abs(xToCanvas(l.position) - loc.x) < 30 && abs(loc.y - beamY) < 60 {
                loads.remove(at: i); diagram.save(loads: loads); invalidate(); return
            }
        }
        for (i, s) in supports.enumerated() {
            if abs(xToCanvas(s.position) - loc.x) < 30 && abs(loc.y - beamY) < 60 {
                supports.remove(at: i); diagram.save(supports: supports); invalidate(); return
            }
        }
    }

    // MARK: - Add-load sheet

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Load at \(String(format: "%.2f", pendingPosition)) m") {
                    HStack {
                        Text(pendingType == .moment ? "Magnitude (kN·m)" : "Magnitude (kN)")
                        Spacer()
                        TextField("kN", text: $pendingMag).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).frame(width: 90)
                    }
                    if pendingType == .distributed {
                        HStack {
                            Text("End position (m)")
                            Spacer()
                            TextField("m", text: $pendingEnd).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing).frame(width: 90)
                        }
                    }
                    Text("Positive = downward / CW").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add \(pendingType.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAddSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { commitLoad() }.disabled((Double(pendingMag) ?? 0) == 0)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func commitLoad() {
        guard let mag = Double(pendingMag) else { return }
        var l = BeamLoad(type: pendingType, position: pendingPosition, magnitude: mag)
        if pendingType == .distributed { l.endPosition = Double(pendingEnd) ?? (pendingPosition + 2) }
        loads.append(l); diagram.save(loads: loads); invalidate(); showAddSheet = false
    }

    // MARK: - Length sheet

    private var lengthSheet: some View {
        NavigationStack {
            Form {
                Section("Beam Length") {
                    HStack { TextField("m", text: $draftLength).keyboardType(.decimalPad); Text("m").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Edit Beam Length")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showLengthSheet = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Set") { commitLength() } }
            }
        }
        .presentationDetents([.height(220)])
        .onAppear { draftLength = String(format: "%.1f", diagram.beamLength) }
    }

    private func commitLength() {
        guard let l = Double(draftLength), l > 0 else { return }
        diagram.beamLength = l
        for i in supports.indices { supports[i].position = min(supports[i].position, l) }
        for i in loads.indices    { loads[i].position    = min(loads[i].position, l) }
        diagram.save(supports: supports); diagram.save(loads: loads); invalidate()
        showLengthSheet = false
    }

    // MARK: - Calculation

    private func invalidate() { xs = []; vs = []; ms = []; ra = nil; rb = nil; solveError = nil }

    private func calculate() {
        solveError = nil
        let sorted = supports.sorted { $0.position < $1.position }
        guard sorted.count == 2 else {
            solveError = "Need exactly 2 supports. Currently \(sorted.count)."; return
        }
        let xA = sorted[0].position, xB = sorted[1].position
        guard xB > xA else { solveError = "Supports must be at different positions."; return }

        var sumMA = 0.0
        for l in loads {
            switch l.type {
            case .point:       sumMA += l.magnitude * (l.position - xA)
            case .distributed:
                let b = l.endPosition ?? (l.position + 1)
                sumMA += l.magnitude * (b - l.position) * ((l.position + b) / 2 - xA)
            case .moment:      sumMA += l.magnitude
            }
        }
        let rbVal = sumMA / (xB - xA)
        let total = loads.reduce(0.0) { acc, l in
            switch l.type {
            case .point:       return acc + l.magnitude
            case .distributed: return acc + l.magnitude * ((l.endPosition ?? (l.position+1)) - l.position)
            case .moment:      return acc
            }
        }
        let raVal = total - rbVal
        ra = raVal; rb = rbVal

        let n = 201
        var xArr = [Double](repeating: 0, count: n)
        var vArr = [Double](repeating: 0, count: n)
        var mArr = [Double](repeating: 0, count: n)
        let L = diagram.beamLength

        for i in 0..<n {
            let x = L * Double(i) / Double(n-1)
            xArr[i] = x
            var v = 0.0
            if x >= xA { v += raVal }
            if x >= xB { v += rbVal }
            for l in loads {
                switch l.type {
                case .point:
                    if x >= l.position { v -= l.magnitude }
                case .distributed:
                    let b = l.endPosition ?? (l.position + 1)
                    if x >= l.position { v -= l.magnitude * (min(x, b) - l.position) }
                case .moment: break
                }
            }
            vArr[i] = v
        }

        let dx = L / Double(n-1)
        for i in 1..<n {
            mArr[i] = mArr[i-1] + 0.5 * (vArr[i-1] + vArr[i]) * dx
            for l in loads where l.type == .moment {
                if l.position > xArr[i-1] && l.position <= xArr[i] { mArr[i] += l.magnitude }
            }
        }
        xs = xArr; vs = vArr; ms = mArr
    }

    // MARK: - V/M diagram sections

    @ViewBuilder
    private func diagramSection(title: String, values: [Double], color: Color) -> some View {
        let h: CGFloat = 160
        let maxAbs = values.map(abs).max() ?? 1
        let scale = maxAbs > 0 ? maxAbs : 1

        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)

            ZStack(alignment: .topLeading) {
                // Gradient background
                LinearGradient(colors: [Color(.systemBackground), Color(.systemGray6)],
                               startPoint: .top, endPoint: .bottom)

                // Curve (Canvas, NO text)
                Canvas { ctx, size in
                    let usable = size.width - paddingX * 2
                    let midY = size.height / 2

                    var zero = Path()
                    zero.move(to: CGPoint(x: paddingX, y: midY))
                    zero.addLine(to: CGPoint(x: paddingX + usable, y: midY))
                    ctx.stroke(zero, with: .color(Color(.systemGray3)), lineWidth: 1)

                    guard values.count > 1 else { return }
                    var fill = Path()
                    fill.move(to: CGPoint(x: paddingX, y: midY))
                    for (i, v) in values.enumerated() {
                        let cx = paddingX + CGFloat(i) / CGFloat(values.count-1) * usable
                        let cy = midY - CGFloat(v / scale) * (h/2 - 18)
                        if i == 0 { fill.move(to: CGPoint(x: cx, y: cy)) } else { fill.addLine(to: CGPoint(x: cx, y: cy)) }
                    }
                    fill.addLine(to: CGPoint(x: paddingX + usable, y: midY))
                    fill.addLine(to: CGPoint(x: paddingX, y: midY))
                    ctx.fill(fill, with: .color(color.opacity(0.22)))

                    var stroke = Path()
                    for (i, v) in values.enumerated() {
                        let cx = paddingX + CGFloat(i) / CGFloat(values.count-1) * usable
                        let cy = midY - CGFloat(v / scale) * (h/2 - 18)
                        if i == 0 { stroke.move(to: CGPoint(x: cx, y: cy)) } else { stroke.addLine(to: CGPoint(x: cx, y: cy)) }
                    }
                    ctx.stroke(stroke, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                .frame(width: canvasW, height: h)

                // Labels as SwiftUI views (safe)
                diagramLabels(values: values, scale: scale, h: h, color: color)
            }
            .frame(width: canvasW, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
            .padding(.horizontal, 16).padding(.bottom, 10)
        }
    }

    private func diagramLabels(values: [Double], scale: Double, h: CGFloat, color: Color) -> some View {
        let usable = canvasW - paddingX * 2
        let midY = h / 2
        return ZStack(alignment: .topLeading) {
            // x-axis labels
            ForEach(0...5, id: \.self) { i in
                let t = Double(i) / 5.0
                let cx = paddingX + CGFloat(t) * usable
                let xVal = diagram.beamLength * t
                Text(String(format: "%.1f", xVal))
                    .font(.system(size: 9)).foregroundStyle(Color(.systemGray))
                    .position(x: cx, y: h - 8)
            }
            // Max/min labels
            if let maxV = values.max(), let maxIdx = values.firstIndex(of: maxV) {
                let cx = paddingX + CGFloat(maxIdx) / CGFloat(values.count-1) * usable
                let cy = midY - CGFloat(maxV / scale) * (h/2 - 18)
                Text(String(format: "%.2f", maxV))
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                    .position(x: cx, y: cy - 9)
            }
            if let minV = values.min(), abs(minV) > 0.01, let minIdx = values.firstIndex(of: minV) {
                let cx = paddingX + CGFloat(minIdx) / CGFloat(values.count-1) * usable
                let cy = midY - CGFloat(minV / scale) * (h/2 - 18)
                Text(String(format: "%.2f", minV))
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                    .position(x: cx, y: cy + 11)
            }
        }
        .frame(width: canvasW, height: h)
        .allowsHitTesting(false)
    }
}
#endif
