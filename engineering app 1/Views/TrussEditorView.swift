#if os(iOS)
import SwiftUI
import SwiftData

// MARK: - Analysis result

private struct MemberResult {
    let ratio: Double      // 0 = no stress, 1 = at capacity, >1 = broken
    let isTension: Bool
    var isBroken: Bool { ratio >= 1.0 }

    var color: Color {
        if isBroken { return .black }
        let r = min(ratio, 1.0)
        if r < 0.5 {
            let t = r / 0.5
            return Color(red: 1, green: 1, blue: 1 - t)        // white → yellow
        } else if r < 0.9 {
            let t = (r - 0.5) / 0.4
            return Color(red: 1, green: 1 - t, blue: 0)        // yellow → red
        } else {
            let t = (r - 0.9) / 0.1
            return Color(red: 1 - 0.8 * t, green: 0, blue: 0) // red → dark red
        }
    }
}

// MARK: - Template

private enum TrussTemplate: String, CaseIterable, Identifiable {
    case warren = "Warren"
    case pratt  = "Pratt"
    case howe   = "Howe"
    case simple = "Simple Beam"
    var id: String { rawValue }
}

// MARK: - Mode

private enum TrussMode { case draw, support, load, erase }

// MARK: - TrussEditorView

struct TrussEditorView: View {
    @Bindable var diagram: TrussDiagram
    var onBack: () -> Void = {}

    // Data
    @State private var nodes:   [TrussNode]   = []
    @State private var members: [TrussMember] = []
    @State private var loads:   [TrussLoad]   = []

    // Interaction
    @State private var mode: TrussMode = .draw
    @State private var selectedNodeID: UUID? = nil

    // Analysis
    @State private var results:        [UUID: MemberResult] = [:]
    @State private var showBreakAlert  = false
    @State private var breakMessage    = ""
    @State private var analysisMessage: String? = nil

    // Car
    @State private var useCarLoad    = false
    @State private var carPosition:  Double = 0.5
    @State private var carAnimating  = false
    @State private var carFloorLevel: Int = 0

    // Load sheet
    @State private var showLoadSheet  = false
    @State private var loadNodeID:    UUID? = nil
    @State private var loadFyText     = "50"
    @State private var loadFxText     = "0"
    @State private var loadLabelText  = "P"

    // Templates
    @State private var showTemplates = false

    // Canvas
    @State private var canvasSize: CGSize = CGSize(width: 700, height: 420)

    // Physics constants
    private let EA: Double = 10_000
    private let memberCapacity: Double = 100
    private let snapRadius: Double = 32

    // MARK: body

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack(alignment: .topLeading) {
                Color(white: 0.14)
                    .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                        guard abs(v.translation.width) < 14,
                              abs(v.translation.height) < 14 else { return }
                        handleBackgroundTap(at: v.location)
                    })

                Canvas { ctx, _ in drawAll(ctx) }
                    .allowsHitTesting(false)

                ForEach(nodes) { n in
                    nodeCircle(n).position(CGPoint(x: n.x, y: n.y))
                }

                if useCarLoad, let cn = carNode {
                    Text("\(Int(diagram.carWeight)) kN")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary)
                        .position(x: cn.x, y: cn.y - 68)
                        .allowsHitTesting(false)
                }

                if useCarLoad {
                    let sliderH = max(120, canvasSize.height * 0.65)
                    VStack(spacing: 6) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Slider(value: $carPosition, in: 0...1)
                            .frame(width: sliderH)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 30, height: sliderH)
                            .onChange(of: carPosition) { _, _ in runAnalysis() }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
                }

                if showBreakAlert { breakAlertOverlay }

                if let msg = analysisMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.88), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                canvasSize = newSize
                injectFloorIfNeeded()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if useCarLoad {
                carPanel
            }
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            nodes   = diagram.loadNodes()
            members = diagram.loadMembers()
            loads   = diagram.loadLoads()
            injectFloorIfNeeded()
        }
        .task(id: carAnimating) {
            guard carAnimating else { return }
            carPosition = 0
            for _ in 0..<21 {
                try? await Task.sleep(for: .milliseconds(180))
                carPosition = min(carPosition + 0.05, 1.0)
                runAnalysis()
                if results.values.contains(where: { $0.isBroken }) {
                    buildBreakMessage()
                    showBreakAlert = true
                    carAnimating = false
                    return
                }
            }
            carAnimating = false
        }
        .onChange(of: useCarLoad) { _, on in
            if on {
                // Default to the bottom chord (highest Y in canvas coords)
                carFloorLevel = max(0, floorLevels.count - 1)
                runAnalysis()
            }
        }
        .sheet(isPresented: $showTemplates) { templateSheet }
        .sheet(isPresented: $showLoadSheet) { loadSheet }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Text(diagram.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: 90)

            toolDivider

            modeBtn("pencil",   active: mode == .draw)    { mode = .draw }
            modeBtn("triangle", active: mode == .support)  { mode = .support }
            modeBtn("arrow.down.circle", active: mode == .load) { mode = .load }
            modeBtn("eraser",   active: mode == .erase)   { mode = .erase }

            toolDivider

            Button { showTemplates = true } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            toolDivider

            Toggle(isOn: $useCarLoad) {
                Image(systemName: "car")
                    .font(.system(size: 12))
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(useCarLoad ? Color.accentColor : .secondary)
            .frame(width: 36)

            toolDivider

            Button {
                runAnalysis()
                if results.values.contains(where: { $0.isBroken }) {
                    buildBreakMessage(); showBreakAlert = true
                }
            } label: {
                Text("Analyze")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            Button {
                // Keep the built-in floor; only clear user-drawn content
                nodes   = nodes.filter(\.isFloor)
                members = members.filter(\.isFloor)
                loads   = []
                results = [:]
                selectedNodeID = nil
                save()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .frame(height: 44)
        .background(.bar)
    }

    private var toolDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 3)
    }

    private func modeBtn(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 28, height: 28)
                .background(active ? Color.accentColor.opacity(0.13) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Car panel

    private var carPanel: some View {
        VStack(spacing: 0) {
            // Floor picker — only for template trusses (no built-in floor) with multiple chords
            let hasBuiltInFloor = nodes.contains(where: \.isFloor)
            let levels = floorLevels
            if !hasBuiltInFloor && levels.count > 1 {
                HStack(spacing: 8) {
                    Label("Deck", systemImage: "road.lanes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $carFloorLevel) {
                        ForEach(levels.indices, id: \.self) { i in
                            Text(floorLevelLabel(i, count: levels.count)).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: carFloorLevel) { _, _ in runAnalysis() }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Weight:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("kN", value: $diagram.carWeight, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.caption)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                    Text("kN")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(carAnimating ? "Stop" : "Simulate") {
                    if carAnimating { carAnimating = false } else { carAnimating = true }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func floorLevelLabel(_ index: Int, count: Int) -> String {
        switch count {
        case 2:  return index == 0 ? "Top" : "Bottom"
        default:
            if index == 0            { return "Top" }
            if index == count - 1    { return "Bottom" }
            return "Mid \(index)"
        }
    }

    // MARK: - Node circle

    private func nodeCircle(_ n: TrussNode) -> some View {
        let isSelected = selectedNodeID == n.id
        let hasLoad    = loads.contains { $0.nodeID == n.id }
        let col: Color = isSelected ? .accentColor
                       : hasLoad    ? .orange
                       : n.isFloor  ? Color(white: 0.56)   // concrete-grey road node
                                    : Color(white: 0.72)
        let size: CGFloat = n.isFloor ? 14 : 16
        return RoundedRectangle(cornerRadius: n.isFloor ? 3 : 8)  // square for floor, circle for user
            .fill(col)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: n.isFloor ? 3 : 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color(white: n.isFloor ? 0.4 : 0.5),
                                  lineWidth: 1.5)
            )
            .allowsHitTesting(false)   // all taps handled by background gesture via snapNode
    }

    // MARK: - Canvas drawing

    private func drawAll(_ ctx: GraphicsContext) {
        // ── Floor beam (road surface) — drawn first so it appears behind members ──
        for m in members where m.isFloor {
            guard let sn = nodeByID(m.startID), let en = nodeByID(m.endID) else { continue }
            var p = Path(); p.move(to: pt(sn)); p.addLine(to: pt(en))
            // Thick concrete-grey slab
            ctx.stroke(p, with: .color(Color(white: 0.32)),
                       style: StrokeStyle(lineWidth: 10, lineCap: .square))
            // Road-surface highlight line
            ctx.stroke(p, with: .color(Color(white: 0.5)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .square))
            // Dashed centre line (lane markings)
            ctx.stroke(p, with: .color(Color.white.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .butt, dash: [8, 5]))
        }

        // ── User-drawn members ──
        for m in members where !m.isFloor {
            guard let sn = nodeByID(m.startID), let en = nodeByID(m.endID) else { continue }
            let res = results[m.id]
            let col: Color = res.map { $0.isBroken ? Color(red: 1, green: 0.1, blue: 0.1) : $0.color }
                             ?? Color(white: 0.5)
            let lw: CGFloat = (res?.isBroken ?? false) ? 4 : 3
            var p = Path(); p.move(to: pt(sn)); p.addLine(to: pt(en))
            ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: lw, lineCap: .round))

            if mode == .erase {
                let mid = CGPoint(x: (sn.x + en.x) / 2, y: (sn.y + en.y) / 2)
                ctx.fill(Path(ellipseIn: CGRect(x: mid.x - 4, y: mid.y - 4, width: 8, height: 8)),
                         with: .color(.red.opacity(0.5)))
            }
        }

        // Support symbols
        for n in nodes {
            if n.isPin   { drawPin(ctx, at: pt(n)) }
            if n.isRoller { drawRoller(ctx, at: pt(n)) }
        }

        // Load arrows
        for load in loads {
            guard let n = nodeByID(load.nodeID) else { continue }
            drawLoadArrow(ctx, at: pt(n), fy: load.fy, fx: load.fx, label: load.label)
        }

        // Car
        if useCarLoad, let cn = carNode {
            drawCar(ctx, at: pt(cn))
            drawLoadArrow(ctx, at: pt(cn), fy: diagram.carWeight, fx: 0, label: "")
        }

        // Ghost member line
        if mode == .draw, let selID = selectedNodeID, let sn = nodeByID(selID) {
            var ghost = Path()
            ghost.move(to: pt(sn))
            ghost.addLine(to: pt(sn))   // will extend on drag; for now just show dot
            ctx.stroke(ghost, with: .color(.clear), lineWidth: 0)
        }
    }

    private func drawPin(_ ctx: GraphicsContext, at p: CGPoint) {
        let s: CGFloat = 14
        var tri = Path()
        tri.move(to: p)
        tri.addLine(to: CGPoint(x: p.x - s, y: p.y + s * 1.4))
        tri.addLine(to: CGPoint(x: p.x + s, y: p.y + s * 1.4))
        tri.closeSubpath()
        ctx.fill(tri, with: .color(Color(white: 0.42)))
        ctx.stroke(tri, with: .color(Color(white: 0.7)), lineWidth: 1.5)
        var gl = Path()
        gl.move(to: CGPoint(x: p.x - s * 1.3, y: p.y + s * 1.4))
        gl.addLine(to: CGPoint(x: p.x + s * 1.3, y: p.y + s * 1.4))
        ctx.stroke(gl, with: .color(Color(white: 0.7)), lineWidth: 2)
    }

    private func drawRoller(_ ctx: GraphicsContext, at p: CGPoint) {
        let r: CGFloat = 7
        let cy = p.y + r + 4
        let rect = CGRect(x: p.x - r, y: cy - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.42)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(Color(white: 0.7)), lineWidth: 1.5)
        var gl = Path()
        gl.move(to: CGPoint(x: p.x - 14, y: cy + r + 3))
        gl.addLine(to: CGPoint(x: p.x + 14, y: cy + r + 3))
        ctx.stroke(gl, with: .color(Color(white: 0.7)), lineWidth: 2)
    }

    private func drawLoadArrow(_ ctx: GraphicsContext, at p: CGPoint,
                                fy: Double, fx: Double, label: String) {
        let len: CGFloat = 48
        let dx = CGFloat(fx), dy = CGFloat(fy)
        let mag = sqrt(dx*dx + dy*dy)
        guard mag > 0 else { return }
        let ux = dx/mag * len, uy = dy/mag * len
        let start = CGPoint(x: p.x - ux, y: p.y - uy)
        var path = Path(); path.move(to: start); path.addLine(to: p)
        ctx.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        let nx = ux/len, ny = uy/len
        let px2 = -ny, py2 = nx
        let hl: CGFloat = 10
        var head = Path()
        head.move(to: p)
        head.addLine(to: CGPoint(x: p.x - nx*hl + px2*5, y: p.y - ny*hl + py2*5))
        head.move(to: p)
        head.addLine(to: CGPoint(x: p.x - nx*hl - px2*5, y: p.y - ny*hl - py2*5))
        ctx.stroke(head, with: .color(.orange), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }

    private func drawCar(_ ctx: GraphicsContext, at p: CGPoint) {
        let w: CGFloat = 52, h: CGFloat = 20, wr: CGFloat = 7
        let top = p.y - h - wr * 2 - 6
        let body = CGRect(x: p.x - w/2, y: top, width: w, height: h)
        ctx.fill(Path(roundedRect: body, cornerRadius: 4), with: .color(Color(white: 0.55)))
        ctx.stroke(Path(roundedRect: body, cornerRadius: 4), with: .color(.white), lineWidth: 1.5)
        for wx in [p.x - w/2 + 7, p.x + w/2 - 7 - wr*2] {
            let wheelRect = CGRect(x: wx, y: top + h, width: wr*2, height: wr*2)
            ctx.fill(Path(ellipseIn: wheelRect), with: .color(Color(white: 0.35)))
            ctx.stroke(Path(ellipseIn: wheelRect), with: .color(.white), lineWidth: 1)
        }
    }

    // MARK: - Interaction

    private func handleBackgroundTap(at point: CGPoint) {
        switch mode {
        case .draw:
            if let snap = snapNode(to: point) {
                handleNodeTap(snap)
            } else {
                let newNode = TrussNode(x: Double(point.x), y: Double(point.y))
                nodes.append(newNode)
                if let selID = selectedNodeID {
                    addMember(from: selID, to: newNode.id)
                }
                // Always select the newly placed node so the chain continues
                selectedNodeID = newNode.id
                save()
            }
        case .support, .load:
            if let snap = snapNode(to: point) { handleNodeTap(snap) }
        case .erase:
            if let snap = snapNode(to: point) {
                handleNodeTap(snap)   // deletes the node + attached members
            } else {
                eraseMemberNear(point)
            }
        }
    }

    private func handleNodeTap(_ n: TrussNode) {
        switch mode {
        case .draw:
            if let selID = selectedNodeID {
                if selID == n.id {
                    selectedNodeID = nil    // tap selected node = stop drawing
                } else {
                    addMember(from: selID, to: n.id)
                    selectedNodeID = n.id  // snap to existing node, keep it selected to branch
                }
            } else {
                selectedNodeID = n.id
            }
        case .support:
            guard let idx = nodes.firstIndex(where: { $0.id == n.id }) else { return }
            if !nodes[idx].isPin && !nodes[idx].isRoller {
                nodes[idx].isPin = true
            } else if nodes[idx].isPin {
                nodes[idx].isPin = false
                nodes[idx].isRoller = true
            } else {
                nodes[idx].isRoller = false
            }
            save()
        case .load:
            loadNodeID = n.id
            if let existing = loads.first(where: { $0.nodeID == n.id }) {
                loadFyText    = String(format: "%.4g", existing.fy)
                loadFxText    = String(format: "%.4g", existing.fx)
                loadLabelText = existing.label
            } else {
                loadFyText = "50"; loadFxText = "0"; loadLabelText = "P"
            }
            showLoadSheet = true
        case .erase:
            guard !n.isFloor else { return }   // built-in floor nodes are permanent
            nodes.removeAll { $0.id == n.id }
            members.removeAll { (!$0.isFloor) && ($0.startID == n.id || $0.endID == n.id) }
            loads.removeAll { $0.nodeID == n.id }
            if selectedNodeID == n.id { selectedNodeID = nil }
            save()
        }
    }

    private func addMember(from startID: UUID, to endID: UUID) {
        guard !members.contains(where: {
            ($0.startID == startID && $0.endID == endID) ||
            ($0.startID == endID   && $0.endID == startID)
        }) else { return }
        members.append(TrussMember(startID: startID, endID: endID))
        save()
    }

    private func eraseMemberNear(_ point: CGPoint) {
        let threshold: Double = 20
        var closest: (UUID, Double)? = nil
        for m in members {
            guard let sn = nodeByID(m.startID), let en = nodeByID(m.endID) else { continue }
            let d = distToSegment(point: point,
                                  a: CGPoint(x: sn.x, y: sn.y),
                                  b: CGPoint(x: en.x, y: en.y))
            if d < threshold { closest = (m.id, d) }
        }
        if let (id, _) = closest {
            guard let m = members.first(where: { $0.id == id }), !m.isFloor else { return }
            members.removeAll { $0.id == id }
            results.removeValue(forKey: id)
            save()
        }
    }

    private func snapNode(to point: CGPoint) -> TrussNode? {
        nodes.min(by: {
            hypot($0.x - Double(point.x), $0.y - Double(point.y)) <
            hypot($1.x - Double(point.x), $1.y - Double(point.y))
        }).flatMap { n in
            hypot(n.x - Double(point.x), n.y - Double(point.y)) < snapRadius ? n : nil
        }
    }

    // MARK: - Analysis

    private func runAnalysis() {
        let r = analyzeTruss()
        results = r
        if members.isEmpty {
            analysisMessage = nil
        } else if r.isEmpty {
            let hasSupport = nodes.contains { $0.isPin || $0.isRoller }
            analysisMessage = hasSupport
                ? "Truss may be underconstrained — check supports and member connectivity"
                : "Add a pin or roller support, then tap Analyze"
        } else {
            analysisMessage = nil
        }
    }

    private func analyzeTruss() -> [UUID: MemberResult] {
        guard nodes.count >= 2, !members.isEmpty else { return [:] }

        let nodeIdx = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        let n = nodes.count
        var fixedDOF = Set<Int>()
        for node in nodes {
            guard let i = nodeIdx[node.id] else { continue }
            if node.isPin    { fixedDOF.insert(2*i); fixedDOF.insert(2*i+1) }
            if node.isRoller { fixedDOF.insert(2*i+1) }
        }
        let freeDOF = (0..<(2*n)).filter { !fixedDOF.contains($0) }
        let nFree = freeDOF.count
        guard nFree > 0 else { return [:] }
        let dofMap = Dictionary(uniqueKeysWithValues: freeDOF.enumerated().map { ($1, $0) })

        struct MD { let id: UUID; let si, ei: Int; let L, c, s: Double }
        var mData: [MD] = []
        var K = Array(repeating: Array(repeating: 0.0, count: nFree), count: nFree)

        for m in members {
            guard let si = nodeIdx[m.startID], let ei = nodeIdx[m.endID] else { continue }
            let dx = nodes[ei].x - nodes[si].x, dy = nodes[ei].y - nodes[si].y
            let L = sqrt(dx*dx + dy*dy); guard L > 0.5 else { continue }
            let c = dx/L, s = dy/L
            mData.append(MD(id: m.id, si: si, ei: ei, L: L, c: c, s: s))
            let k = EA / L
            let dofs = [2*si, 2*si+1, 2*ei, 2*ei+1]
            let loc: [[Double]] = [[c*c, c*s, -c*c, -c*s],
                                   [c*s, s*s, -c*s, -s*s],
                                   [-c*c,-c*s, c*c,  c*s],
                                   [-c*s,-s*s, c*s,  s*s]]
            for (r, dr) in dofs.enumerated() {
                guard let fr = dofMap[dr] else { continue }
                for (col, dc) in dofs.enumerated() {
                    guard let fc = dofMap[dc] else { continue }
                    K[fr][fc] += k * loc[r][col]
                }
            }
        }

        var F = Array(repeating: 0.0, count: nFree)
        for load in effectiveLoads {
            guard let ni = nodeIdx[load.nodeID] else { continue }
            if let fi = dofMap[2*ni]   { F[fi]   += load.fx }
            if let fi = dofMap[2*ni+1] { F[fi]   += load.fy }
        }

        guard let uFree = solveLinear(K, F) else { return [:] }
        var U = Array(repeating: 0.0, count: 2*n)
        for (i, di) in freeDOF.enumerated() { U[di] = uFree[i] }

        var out = [UUID: MemberResult]()
        for md in mData {
            let du = U[2*md.ei] - U[2*md.si], dv = U[2*md.ei+1] - U[2*md.si+1]
            let force = EA / md.L * (du * md.c + dv * md.s)
            out[md.id] = MemberResult(ratio: abs(force) / memberCapacity, isTension: force > 0)
        }
        return out
    }

    private func solveLinear(_ A: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count; guard n > 0 else { return [] }
        var M = A; var rhs = b
        for col in 0..<n {
            var maxRow = col
            for row in (col+1)..<n { if abs(M[row][col]) > abs(M[maxRow][col]) { maxRow = row } }
            M.swapAt(col, maxRow); rhs.swapAt(col, maxRow)
            guard abs(M[col][col]) > 1e-12 else { return nil }
            let piv = M[col][col]
            for c in col..<n { M[col][c] /= piv }
            rhs[col] /= piv
            for row in 0..<n where row != col {
                let f = M[row][col]; guard abs(f) > 1e-14 else { continue }
                for c in col..<n { M[row][c] -= f * M[col][c] }
                rhs[row] -= f * rhs[col]
            }
        }
        return rhs
    }

    private var effectiveLoads: [TrussLoad] {
        var all = loads
        if useCarLoad, let cn = carNode {
            all.append(TrussLoad(nodeID: cn.id, fy: diagram.carWeight, fx: 0, label: "Car"))
        }
        return all
    }

    /// Distinct Y-levels detected in the truss, sorted top-to-bottom (small → large Y).
    /// Nodes within 8% of canvas height of each other are grouped into one level.
    private var floorLevels: [Double] {
        guard !nodes.isEmpty else { return [] }
        let threshold = max(30.0, canvasSize.height * 0.08)
        var levels: [Double] = []
        for y in nodes.map(\.y).sorted() {
            if levels.isEmpty || abs(y - levels.last!) > threshold {
                levels.append(y)
            }
        }
        return levels
    }

    private var carNode: TrussNode? {
        // Prefer built-in floor nodes (the designated road surface)
        let floorNds = nodes.filter(\.isFloor).sorted { $0.x < $1.x }
        if !floorNds.isEmpty {
            let minX = floorNds.first!.x, maxX = floorNds.last!.x
            guard maxX > minX else { return floorNds.first }
            let targetX = minX + carPosition * (maxX - minX)
            return floorNds.min(by: { abs($0.x - targetX) < abs($1.x - targetX) })
        }
        // Fallback: level-based detection for template trusses (no built-in floor)
        let levels = floorLevels
        guard !levels.isEmpty else { return nil }
        let idx = min(max(carFloorLevel, 0), levels.count - 1)
        let targetY = levels[idx]
        let threshold = max(30.0, canvasSize.height * 0.08)
        let levelNodes = nodes.filter { abs($0.y - targetY) < threshold }.sorted { $0.x < $1.x }
        guard !levelNodes.isEmpty else { return nil }
        let minX = levelNodes.first!.x, maxX = levelNodes.last!.x
        guard maxX > minX else { return levelNodes.first }
        let targetX = minX + carPosition * (maxX - minX)
        return levelNodes.min(by: { abs($0.x - targetX) < abs($1.x - targetX) })
    }

    private func buildBreakMessage() {
        let broken = members.filter { results[$0.id]?.isBroken ?? false }
        guard !broken.isEmpty else { return }
        let names = broken.compactMap { m -> String? in
            guard let sn = nodeByID(m.startID), let en = nodeByID(m.endID) else { return nil }
            let dy = abs(sn.y - en.y), dx = abs(sn.x - en.x)
            if dy < 12 { return "chord" }
            if dx < 12 { return "vertical" }
            return "diagonal"
        }
        let types = Set(names).joined(separator: ", ")
        breakMessage = "Failure in \(types) member\(broken.count > 1 ? "s" : "")."
    }

    // MARK: - Break alert overlay

    private var breakAlertOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { showBreakAlert = false }
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)
                Text("Bridge Failure")
                    .font(.headline)
                Text(breakMessage)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                Button("OK") { showBreakAlert = false }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 10)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(28)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Templates

    private var templateSheet: some View {
        NavigationStack {
            List {
                ForEach(TrussTemplate.allCases) { tmpl in
                    Button(tmpl.rawValue) {
                        applyTemplate(tmpl)
                        showTemplates = false
                    }
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTemplates = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func applyTemplate(_ t: TrussTemplate) {
        let (n, m) = buildTemplate(t)
        // Templates provide their own bottom chord — no built-in floor needed
        nodes = n; members = m; loads = []
        results = [:]; selectedNodeID = nil
        save()
    }

    private func buildTemplate(_ t: TrussTemplate) -> ([TrussNode], [TrussMember]) {
        let panels = 6
        let xS = canvasSize.width * 0.08
        let span = canvasSize.width * 0.84
        let yB = canvasSize.height * 0.72
        let yT = canvasSize.height * 0.32
        let pw = span / Double(panels)

        var ns: [TrussNode] = []
        // Bottom chord B[0..panels]
        for i in 0...panels {
            var n = TrussNode(x: xS + Double(i)*pw, y: yB)
            if i == 0        { n.isPin    = true }
            if i == panels   { n.isRoller = true }
            ns.append(n)
        }
        // Top chord T[0..panels]
        for i in 0...panels {
            ns.append(TrussNode(x: xS + Double(i)*pw, y: yT))
        }
        let B = Array(0...panels)
        let T = Array((panels+1)...(2*panels+1))

        var ms: [TrussMember] = []
        func link(_ a: Int, _ b: Int) { ms.append(TrussMember(startID: ns[a].id, endID: ns[b].id)) }

        // Chords
        for i in 0..<panels { link(B[i], B[i+1]); link(T[i], T[i+1]) }

        // Verticals (all templates except Warren)
        if t != .warren {
            for i in 0...panels { link(B[i], T[i]) }
        } else {
            // End verticals only for Warren
            link(B[0], T[0]); link(B[panels], T[panels])
        }

        // Diagonals
        switch t {
        case .warren:
            for i in 0..<panels {
                if i % 2 == 0 { link(B[i], T[i+1]) } else { link(T[i], B[i+1]) }
            }
        case .pratt:
            for i in 0..<panels/2      { link(T[i], B[i+1]) }
            for i in panels/2..<panels { link(T[i+1], B[i]) }
        case .howe:
            for i in 0..<panels/2      { link(B[i], T[i+1]) }
            for i in panels/2..<panels { link(B[i+1], T[i]) }
        case .simple:
            break
        }

        return (ns, ms)
    }

    // MARK: - Load sheet

    private var loadSheet: some View {
        NavigationStack {
            Form {
                Section("Vertical load (↓ = positive)") {
                    HStack {
                        TextField("kN", text: $loadFyText).keyboardType(.decimalPad)
                        Text("kN").foregroundStyle(.secondary)
                    }
                }
                Section("Horizontal load (→ = positive)") {
                    HStack {
                        TextField("kN", text: $loadFxText).keyboardType(.decimalPad)
                        Text("kN").foregroundStyle(.secondary)
                    }
                }
                Section("Label") {
                    TextField("P", text: $loadLabelText)
                }
                Section {
                    Button("Remove load", role: .destructive) {
                        if let id = loadNodeID { loads.removeAll { $0.nodeID == id } }
                        save(); showLoadSheet = false
                    }
                    .disabled(loads.first(where: { $0.nodeID == loadNodeID }) == nil)
                }
            }
            .navigationTitle("Point Load")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showLoadSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { commitLoad() }
                }
            }
        }
        .presentationDetents([.height(380)])
    }

    private func commitLoad() {
        guard let nid = loadNodeID,
              let fy = Double(loadFyText) else { showLoadSheet = false; return }
        let fx = Double(loadFxText) ?? 0
        loads.removeAll { $0.nodeID == nid }
        loads.append(TrussLoad(nodeID: nid, fy: fy, fx: fx,
                               label: loadLabelText.isEmpty ? "P" : loadLabelText))
        save(); showLoadSheet = false
    }

    // MARK: - Built-in floor injection

    /// Adds a permanent road-surface beam across the bottom of the canvas the
    /// first time a custom diagram is opened (or after the user clears it).
    /// Template trusses deliberately skip this because their bottom chord is the road.
    private func injectFloorIfNeeded() {
        guard canvasSize.width > 0, canvasSize.height > 0,
              !nodes.contains(where: \.isFloor) else { return }

        let nFloor = 9
        let yFloor = canvasSize.height * 0.78
        let xStart = canvasSize.width  * 0.05
        let xEnd   = canvasSize.width  * 0.95
        let dx     = (xEnd - xStart) / Double(nFloor - 1)

        var fNodes: [TrussNode] = []
        for i in 0..<nFloor {
            var n = TrussNode(x: xStart + Double(i) * dx, y: yFloor)
            n.isFloor  = true
            n.isPin    = (i == 0)
            n.isRoller = (i == nFloor - 1)
            fNodes.append(n)
        }

        var fMembers: [TrussMember] = []
        for i in 0..<(nFloor - 1) {
            var m = TrussMember(startID: fNodes[i].id, endID: fNodes[i + 1].id)
            m.isFloor = true
            fMembers.append(m)
        }

        nodes.append(contentsOf: fNodes)
        members.append(contentsOf: fMembers)
        save()
    }

    // MARK: - Helpers

    private func nodeByID(_ id: UUID) -> TrussNode? { nodes.first { $0.id == id } }
    private func pt(_ n: TrussNode) -> CGPoint { CGPoint(x: n.x, y: n.y) }

    private func distToSegment(point p: CGPoint, a: CGPoint, b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx*dx + dy*dy
        guard lenSq > 0 else { return hypot(Double(p.x-a.x), Double(p.y-a.y)) }
        let t = max(0, min(1, Double(((p.x-a.x)*dx + (p.y-a.y)*dy) / lenSq)))
        return hypot(Double(p.x) - (Double(a.x) + t*Double(dx)),
                     Double(p.y) - (Double(a.y) + t*Double(dy)))
    }

    private func save() {
        diagram.save(nodes: nodes)
        diagram.save(members: members)
        diagram.save(loads: loads)
    }
}
#endif
