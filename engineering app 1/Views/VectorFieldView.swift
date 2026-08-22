//
//  VectorFieldView.swift
//  Tolerance
//
//  Vector Field & Flow Diagram.
//  Full-screen field canvas (dark toned background). Arrow colours encode magnitude.
//  No text inside Canvas closures (avoids iOS Canvas-Text crash).
//

#if os(iOS)
import SwiftUI
import SwiftData

struct VectorFieldView: View {
    @Bindable var diagram: VectorFieldDiagram
    var onBack: () -> Void = {}

    @State private var sources:        [FieldSource]  = []
    @State private var eraseMode       = false
    @State private var addPositive     = true
    @State private var selectedType:   VectorFieldType = .uniform
    @State private var uniformAngle:   Double = 0
    @State private var uniformMag:     Double = 1

    private let canvasW:  CGFloat = 900
    private let canvasH:  CGFloat = 620
    private let gridStep: CGFloat = 54

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if selectedType == .uniform { uniformBar; Divider() }
            else                        { hintBar;    Divider() }
            fieldArea
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            sources      = diagram.loadSources()
            selectedType = diagram.fieldType
            uniformAngle = diagram.uniformAngle
            uniformMag   = diagram.uniformMagnitude
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }.buttonStyle(.plain)

            Text(diagram.title)
                .font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: 120)

            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 20).padding(.horizontal, 4)

            Picker("", selection: $selectedType) {
                ForEach(VectorFieldType.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .onChange(of: selectedType) { _, t in
                diagram.fieldType = t
                sources = []; diagram.save(sources: [])
            }

            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 20).padding(.horizontal, 4)

            if selectedType != .uniform {
                Button { addPositive.toggle() } label: {
                    Label(addPositive ? "+" : "−", systemImage: addPositive ? "plus.circle" : "minus.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(addPositive ? Color.cyan : Color.orange)
                        .padding(.horizontal, 8).frame(height: 26)
                        .background((addPositive ? Color.cyan : Color.orange).opacity(0.15), in: Capsule())
                }.buttonStyle(.plain)

                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 20).padding(.horizontal, 4)
            }

            Button { eraseMode.toggle() } label: {
                Image(systemName: "eraser")
                    .foregroundStyle(eraseMode ? Color.red : Color.secondary)
                    .frame(width: 30, height: 30)
                    .background(eraseMode ? Color.red.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain)

            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 20).padding(.horizontal, 4)

            Button {
                sources = []; diagram.save(sources: [])
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(sources.isEmpty ? Color.secondary : Color.red)
                    .frame(width: 30, height: 30)
            }.buttonStyle(.plain).disabled(sources.isEmpty)
        }
        .frame(height: 36)
        .background(.bar)
    }

    private var uniformBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
            Slider(value: $uniformAngle, in: 0...360) { _ in
                diagram.uniformAngle = uniformAngle
            }
            Text("\(Int(uniformAngle))°").font(.caption.monospacedDigit()).frame(width: 38)
            Divider().frame(height: 16)
            Image(systemName: "arrow.up.and.down").font(.caption).foregroundStyle(.secondary)
            Slider(value: $uniformMag, in: 0.1...3) { _ in
                diagram.uniformMagnitude = uniformMag
            }
            Text("×\(String(format: "%.1f", uniformMag))").font(.caption.monospacedDigit()).frame(width: 40)
        }
        .padding(.horizontal, 14).frame(height: 30)
        .background(Color(.secondarySystemBackground))
    }

    private var hintBar: some View {
        HStack {
            Text(selectedType.hint).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text("\(sources.count) source\(sources.count == 1 ? "" : "s")")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).frame(height: 28)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Field area (full-screen dark canvas)

    private var fieldArea: some View {
        ZStack {
            // Dark background — field canvas is the content, no white padding
            Color(red: 0.07, green: 0.07, blue: 0.12)
                .ignoresSafeArea()

            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Canvas { ctx, _ in
                    drawGrid(ctx)
                    drawArrows(ctx)
                    drawSourceMarkers(ctx)
                }
                .frame(width: canvasW, height: canvasH)
                .onTapGesture(coordinateSpace: .local) { handleTap(at: $0) }
            }
        }
    }

    // MARK: - Canvas drawing (NO text anywhere)

    private func drawGrid(_ ctx: GraphicsContext) {
        var p = Path()
        var x: CGFloat = 0
        while x <= canvasW { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: canvasH)); x += gridStep }
        var y: CGFloat = 0
        while y <= canvasH { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: canvasW, y: y)); y += gridStep }
        ctx.stroke(p, with: .color(Color.white.opacity(0.06)), lineWidth: 0.4)
    }

    private func drawArrows(_ ctx: GraphicsContext) {
        var rawMags: [CGFloat] = []
        struct Arr { var cx, cy, vx, vy: CGFloat }
        var arrows: [Arr] = []

        var gx = gridStep / 2
        while gx < canvasW {
            var gy = gridStep / 2
            while gy < canvasH {
                let (vx, vy) = fieldAt(Double(gx), Double(gy))
                let mag = CGFloat(sqrt(vx*vx + vy*vy))
                rawMags.append(mag)
                arrows.append(Arr(cx: gx, cy: gy, vx: CGFloat(vx), vy: CGFloat(vy)))
                gy += gridStep
            }
            gx += gridStep
        }

        let maxMag = rawMags.max() ?? 1
        guard maxMag > 0 else { return }
        let sc = CGFloat(gridStep * 0.44) / maxMag

        for a in arrows {
            let mag = sqrt(a.vx*a.vx + a.vy*a.vy)
            guard mag > 0.0005 * maxMag else { continue }
            let col = arrowColor(mag / maxMag)
            let dx = a.vx * sc, dy = a.vy * sc
            let tip = CGPoint(x: a.cx + dx, y: a.cy + dy)
            var s = Path(); s.move(to: CGPoint(x: a.cx, y: a.cy)); s.addLine(to: tip)
            ctx.stroke(s, with: .color(col), lineWidth: 1.1)
            drawHead(ctx, tip: tip, dx: dx, dy: dy, col: col)
        }
    }

    private func drawHead(_ ctx: GraphicsContext, tip: CGPoint, dx: CGFloat, dy: CGFloat, col: Color) {
        let l = hypot(dx, dy); guard l > 0 else { return }
        let bx = -dx/l, by = -dy/l
        let c = CGFloat(cos(0.4)), s = CGFloat(sin(0.4))
        let hl: CGFloat = 5
        var h = Path()
        h.move(to: tip)
        h.addLine(to: CGPoint(x: tip.x + hl*(bx*c - by*s), y: tip.y + hl*(bx*s + by*c)))
        h.move(to: tip)
        h.addLine(to: CGPoint(x: tip.x + hl*(bx*c + by*s), y: tip.y + hl*(-bx*s + by*c)))
        ctx.stroke(h, with: .color(col), lineWidth: 1.1)
    }

    private func drawSourceMarkers(_ ctx: GraphicsContext) {
        for src in sources {
            let cx = CGFloat(src.x), cy = CGFloat(src.y)
            let col: Color = src.strength >= 0 ? .cyan : .orange
            ctx.fill(Path(ellipseIn: CGRect(x: cx-9, y: cy-9, width: 18, height: 18)),
                     with: .color(col.opacity(0.9)))
            ctx.stroke(Path(ellipseIn: CGRect(x: cx-9, y: cy-9, width: 18, height: 18)),
                        with: .color(.white.opacity(0.6)), lineWidth: 1)
        }
    }

    // MARK: - Field computation

    private func fieldAt(_ x: Double, _ y: Double) -> (Double, Double) {
        switch selectedType {
        case .uniform:
            let r = uniformAngle * .pi / 180
            return (cos(r) * uniformMag, -sin(r) * uniformMag)
        case .source:
            var fx = 0.0, fy = 0.0
            for s in sources {
                let dx = x - s.x, dy = y - s.y
                let r2 = max(dx*dx + dy*dy, 100), r = sqrt(r2)
                fx += s.strength * dx / r; fy += s.strength * dy / r
            }
            return (fx, fy)
        case .vortex:
            var fx = 0.0, fy = 0.0
            for s in sources {
                let dx = x - s.x, dy = y - s.y
                let r2 = max(dx*dx + dy*dy, 100)
                fx += s.strength * (-dy) / r2; fy += s.strength * dx / r2
            }
            return (fx, fy)
        }
    }

    private func arrowColor(_ t: CGFloat) -> Color {
        let clamped = min(max(t, 0), 1)
        // Blue (low) → cyan → green → yellow → red (high)
        return Color(hue: Double(0.67 - clamped * 0.67), saturation: 0.9, brightness: 0.95)
    }

    // MARK: - Tap handling

    private func handleTap(at loc: CGPoint) {
        guard selectedType != .uniform else { return }
        if eraseMode {
            if let idx = sources.indices.min(by: {
                hypot(sources[$0].x - Double(loc.x), sources[$0].y - Double(loc.y)) <
                hypot(sources[$1].x - Double(loc.x), sources[$1].y - Double(loc.y))
            }), hypot(sources[idx].x - Double(loc.x), sources[idx].y - Double(loc.y)) < 32 {
                sources.remove(at: idx); diagram.save(sources: sources)
            }
            return
        }
        sources.append(FieldSource(x: Double(loc.x), y: Double(loc.y),
                                   strength: addPositive ? 200.0 : -200.0))
        diagram.save(sources: sources)
    }
}
#endif
