//
//  CircuitSymbolView.swift
//  Tolerance
//
//  Renders one component's IEEE/IEC-style schematic symbol plus its
//  tappable terminal dots. Split out of CircuitEditorView.swift once the
//  digital gate/mux/flip-flop/clock symbols were added (the original file
//  was already 1400+ lines).
//
//  Terminal dots are driven entirely by `component.type.pins()` — the same
//  table CircuitNetlist and CircuitComponent.pinPosition(_:) use — so every
//  component, whether a 2-terminal analog part or an N-pin digital gate,
//  is positioned and hit-tested through one shared source of truth.
//

#if os(iOS)
import SwiftUI

struct CircuitSymbolView: View {
    let component: CircuitComponent
    let isSelected: Bool
    /// Terminal dots only render/respond to taps in wire mode, so they
    /// never steal a tap meant for select/erase/value-edit the rest of the time.
    var isWireMode: Bool = false
    /// LEDs only: true when the digital simulator has found this LED's net
    /// at logic HIGH. Ignored by every other component type; always false
    /// in analog mode, which keeps its original, unconditional LED look.
    var isLit: Bool = false
    /// Called with the tapped pin's id (e.g. "A"/"B", or "OUT"/"CLK" for
    /// digital parts). The caller (CircuitEditorView) resolves the actual
    /// canvas-space point via `component.pinPosition(_:)`, so a tapped
    /// terminal always lines up exactly with where a wire would snap to.
    var onTerminalTap: ((String) -> Void)? = nil

    /// Two-terminal analog parts keep the original compact 88×50 frame.
    /// Multi-pin digital parts (two inputs at local y = ∓44, i.e. a full
    /// grid unit above/below center) need a taller 88×100 frame so those
    /// pins land inside the view instead of clipping past its edge.
    private var frameSize: CGSize {
        switch component.type {
        case .andGate, .orGate, .nandGate, .norGate, .xorGate, .xnorGate, .mux2to1, .dFlipFlop:
            return CGSize(width: 88, height: 100)
        default:
            return CGSize(width: 88, height: 50)
        }
    }
    private var W: CGFloat { frameSize.width }
    private var H: CGFloat { frameSize.height }

    /// Terminal dots, in this view's own unrotated local coordinates —
    /// SwiftUI's rotationEffect on the enclosing frame carries them around
    /// with the drawn symbol automatically. local offset (0,0) is the
    /// component's center, i.e. (W/2, H/2) in this view's own space —
    /// matching the ComponentPin.localOffset convention exactly.
    private var terminalPoints: [(pinID: String, point: CGPoint)] {
        let cx = W / 2, cy = H / 2
        return component.type.pins().map { pin in
            (pin.id, CGPoint(x: cx + pin.localOffset.x, y: cy + pin.localOffset.y))
        }
    }

    var body: some View {
        ZStack {
            ZStack {
                Canvas { ctx, size in
                    CircuitSymbolDrawer.draw(component: component, in: ctx, size: size, isLit: isLit)
                }

                if isWireMode {
                    ForEach(terminalPoints, id: \.pinID) { term in
                        Circle()
                            .fill(Color.cyan.opacity(0.85))
                            .frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
                            .position(term.point)
                            .contentShape(Circle())
                            .onTapGesture { onTerminalTap?(term.pinID) }
                    }
                }
            }
            .frame(width: W, height: H)
            .rotationEffect(.degrees(component.rotation))

            Text(labelText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize()
                .frame(maxWidth: W + 20)
                .offset(y: H / 2 + 12)
        }
        .frame(width: W + 20, height: H + 30)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1.5)
                    .frame(width: W + 12, height: H + 12)
            }
        }
        .contentShape(Rectangle())
    }

    private var labelText: String {
        component.value != nil
            ? "\(component.label): \(component.valueString)"
            : component.label
    }
}

// MARK: - Symbol drawing

enum CircuitSymbolDrawer {
    static func draw(component: CircuitComponent, in ctx: GraphicsContext, size: CGSize, isLit: Bool = false) {
        let cx = size.width / 2, cy = size.height / 2
        let tw = size.width / 2 - 2

        switch component.type {
        case .resistor:   drawResistor(ctx, cx, cy, tw)
        case .battery:    drawBattery(ctx, cx, cy, tw)
        case .capacitor:  drawCapacitor(ctx, cx, cy, tw)
        case .inductor:   drawInductor(ctx, cx, cy, tw)
        case .led:        drawLED(ctx, cx, cy, tw, isLit: isLit)
        case .switchComp: drawSwitch(ctx, cx, cy, tw, closed: component.isClosed)
        case .ground:     drawGround(ctx, cx, cy)
        case .voltmeter:  drawMeter(ctx, cx, cy, tw, label: "V")
        case .ammeter:    drawMeter(ctx, cx, cy, tw, label: "A")
        case .andGate:    drawAndOrGate(ctx, cx, cy, kind: .and, bubble: false)
        case .nandGate:   drawAndOrGate(ctx, cx, cy, kind: .and, bubble: true)
        case .orGate:     drawAndOrGate(ctx, cx, cy, kind: .or, bubble: false)
        case .norGate:    drawAndOrGate(ctx, cx, cy, kind: .or, bubble: true)
        case .xorGate:    drawAndOrGate(ctx, cx, cy, kind: .xor, bubble: false)
        case .xnorGate:   drawAndOrGate(ctx, cx, cy, kind: .xor, bubble: true)
        case .notGate:    drawNotGate(ctx, cx, cy)
        case .mux2to1:    drawMux(ctx, cx, cy)
        case .dFlipFlop:  drawFlipFlop(ctx, cx, cy)
        case .clock:      drawClock(ctx, cx, cy, tw)
        }
    }

    private static let wire = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)

    private static func drawResistor(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ tw: CGFloat) {
        let bw: CGFloat = 28; let bh: CGFloat = 16
        var leads = Path()
        leads.move(to: CGPoint(x: cx - tw,   y: cy)); leads.addLine(to: CGPoint(x: cx - bw/2, y: cy))
        leads.move(to: CGPoint(x: cx + bw/2, y: cy)); leads.addLine(to: CGPoint(x: cx + tw,   y: cy))
        ctx.stroke(leads, with: .color(Color.primary), style: wire)
        var box = Path()
        box.addRect(CGRect(x: cx - bw/2, y: cy - bh/2, width: bw, height: bh))
        ctx.stroke(box, with: .color(Color.primary), lineWidth: 1.8)
    }

    private static func drawBattery(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ tw: CGFloat) {
        let gap: CGFloat = 5; let lh: CGFloat = 22; let sh: CGFloat = 13
        var p = Path()
        p.move(to: CGPoint(x: cx - tw,  y: cy)); p.addLine(to: CGPoint(x: cx - gap, y: cy))
        p.move(to: CGPoint(x: cx + gap, y: cy)); p.addLine(to: CGPoint(x: cx + tw,  y: cy))
        p.move(to: CGPoint(x: cx - gap, y: cy - lh/2)); p.addLine(to: CGPoint(x: cx - gap, y: cy + lh/2))
        p.move(to: CGPoint(x: cx + gap, y: cy - sh/2)); p.addLine(to: CGPoint(x: cx + gap, y: cy + sh/2))
        ctx.stroke(p, with: .color(Color.primary), style: StrokeStyle(lineWidth: 2.0, lineCap: .square))
        ctx.draw(Text("+").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.primary),
                 at: CGPoint(x: cx - gap - 8, y: cy - lh/2))
        ctx.draw(Text("−").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.primary),
                 at: CGPoint(x: cx + gap + 8, y: cy - sh/2))
    }

    private static func drawCapacitor(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ tw: CGFloat) {
        let gap: CGFloat = 5; let ph: CGFloat = 24
        var p = Path()
        p.move(to: CGPoint(x: cx - tw,  y: cy)); p.addLine(to: CGPoint(x: cx - gap, y: cy))
        p.move(to: CGPoint(x: cx + gap, y: cy)); p.addLine(to: CGPoint(x: cx + tw,  y: cy))
        p.move(to: CGPoint(x: cx - gap, y: cy - ph/2)); p.addLine(to: CGPoint(x: cx - gap, y: cy + ph/2))
        p.move(to: CGPoint(x: cx + gap, y: cy - ph/2)); p.addLine(to: CGPoint(x: cx + gap, y: cy + ph/2))
        ctx.stroke(p, with: .color(Color.primary), style: StrokeStyle(lineWidth: 2.0, lineCap: .square))
    }

    private static func drawInductor(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ tw: CGFloat) {
        let r: CGFloat = 6; let n = 4
        let totalW = CGFloat(n) * r * 2; let sx = cx - totalW / 2
        var p = Path()
        p.move(to: CGPoint(x: cx - tw, y: cy)); p.addLine(to: CGPoint(x: sx, y: cy))
        for i in 0..<n {
            p.addArc(center: CGPoint(x: sx + CGFloat(i) * r * 2 + r, y: cy),
                     radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        }
        p.addLine(to: CGPoint(x: cx + tw, y: cy))
        ctx.stroke(p, with: .color(Color.primary), style: wire)
    }

    private static func drawLED(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ tw: CGFloat,
                                isLit: Bool = false) {
        let th: CGFloat = 16
        var leads = Path()
        leads.move(to: CGPoint(x: cx - tw,   y: cy)); leads.addLine(to: CGPoint(x: cx - th/2, y: cy))
        leads.move(to: CGPoint(x: cx + th/2, y: cy)); leads.addLine(to: CGPoint(x: cx + tw,   y: cy))
        leads.move(to: CGPoint(x: cx + th/2, y: cy - th/2))
        leads.addLine(to: CGPoint(x: cx + th/2, y: cy + th/2))
        ctx.stroke(leads, with: .color(Color.primary), style: wire)

        if isLit {
            ctx.fill(Path(ellipseIn: CGRect(x: cx - th, y: cy - th, width: th * 2, height: th * 2)),
                      with: .color(.yellow.opacity(0.35)))
        }

        var tri = Path()
        tri.move(to: CGPoint(x: cx - th/2, y: cy - th/2))
        tri.addLine(to: CGPoint(x: cx + th/2, y: cy))
        tri.addLine(to: CGPoint(x: cx - th/2, y: cy + th/2))
        tri.closeSubpath()
        ctx.fill(tri, with: .color(.yellow.opacity(isLit ? 0.9 : 0.35)))
        ctx.stroke(tri, with: .color(Color.primary), lineWidth: 1.6)
        var arrows = Path()
        for i in 0..<2 {
            let d = CGFloat(i) * 5
            arrows.move(to: CGPoint(x: cx + th/2 + 4 + d, y: cy - th/2 + d))
            arrows.addLine(to: CGPoint(x: cx + th/2 + 10 + d, y: cy - th/2 - 6 + d))
        }
        ctx.stroke(arrows, with: .color(.yellow.opacity(0.9)),
                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    private static func drawSwitch(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat,
                                   _ tw: CGFloat, closed: Bool) {
        let px: CGFloat = 14; let dr: CGFloat = 2.5
        var p = Path()
        p.move(to: CGPoint(x: cx - tw, y: cy)); p.addLine(to: CGPoint(x: cx - px, y: cy))
        p.move(to: CGPoint(x: cx + px, y: cy)); p.addLine(to: CGPoint(x: cx + tw, y: cy))
        if closed {
            p.move(to: CGPoint(x: cx - px, y: cy)); p.addLine(to: CGPoint(x: cx + px, y: cy))
        } else {
            p.move(to: CGPoint(x: cx - px, y: cy)); p.addLine(to: CGPoint(x: cx + px - 4, y: cy - 14))
        }
        ctx.stroke(p, with: .color(Color.primary), style: wire)
        for dx: CGFloat in [-px, px] {
            ctx.fill(Path(ellipseIn: CGRect(x: cx + dx - dr, y: cy - dr, width: dr * 2, height: dr * 2)),
                     with: .color(Color.primary))
        }
    }

    private static func drawGround(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat) {
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy - 16)); p.addLine(to: CGPoint(x: cx, y: cy))
        zip([22, 14, 7] as [CGFloat], [0, 6, 12] as [CGFloat]).forEach { (w, dy) in
            p.move(to: CGPoint(x: cx - w/2, y: cy + dy))
            p.addLine(to: CGPoint(x: cx + w/2, y: cy + dy))
        }
        ctx.stroke(p, with: .color(Color.primary), style: StrokeStyle(lineWidth: 1.8, lineCap: .square))
    }

    private static func drawMeter(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat,
                                  _ tw: CGFloat, label: String) {
        let r: CGFloat = 14
        var p = Path()
        p.move(to: CGPoint(x: cx - tw, y: cy)); p.addLine(to: CGPoint(x: cx - r, y: cy))
        p.move(to: CGPoint(x: cx + r,  y: cy)); p.addLine(to: CGPoint(x: cx + tw, y: cy))
        p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        ctx.stroke(p, with: .color(Color.primary), style: wire)
        ctx.draw(Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.primary),
                 at: CGPoint(x: cx, y: cy))
    }

    // MARK: - Digital gates
    //
    // All gate bodies are sized to sit inside a ±44 (one grid unit) input
    // span, matching CircuitComponentType.pins() exactly: two input leads
    // enter at local y = ∓44, jog inward, and land on the body's flat left
    // edge at y = ∓bodyHalfHeight; the output lead leaves the body's tip
    // straight out to local (44, 0).

    private enum GateKind { case and, or, xor }

    /// AND/NAND/OR/NOR/XOR/XNOR all share the same input-lead jog and
    /// output-lead geometry; only the body outline (and an optional extra
    /// curved line for XOR/XNOR) and the optional inversion bubble differ.
    private static func drawAndOrGate(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat,
                                      kind: GateKind, bubble: Bool) {
        let bodyHalfHeight: CGFloat = 18
        let bodyWidth: CGFloat = 26
        let leftX = cx - bodyWidth / 2
        let topY = cy - bodyHalfHeight
        let botY = cy + bodyHalfHeight

        var leads = Path()
        leads.addPath(orthogonalLead(from: CGPoint(x: cx - 44, y: cy - 44), bodyEdgeX: leftX, bodyY: topY + 6))
        leads.addPath(orthogonalLead(from: CGPoint(x: cx - 44, y: cy + 44), bodyEdgeX: leftX, bodyY: botY - 6))
        ctx.stroke(leads, with: .color(Color.primary), style: wire)

        var body = Path()
        var tipX: CGFloat

        switch kind {
        case .and:
            let midX = leftX + bodyWidth / 2
            body.move(to: CGPoint(x: leftX, y: topY))
            body.addLine(to: CGPoint(x: midX, y: topY))
            body.addArc(center: CGPoint(x: midX, y: cy), radius: bodyHalfHeight,
                        startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            body.addLine(to: CGPoint(x: leftX, y: botY))
            body.closeSubpath()
            tipX = midX + bodyHalfHeight

        case .or, .xor:
            tipX = leftX + bodyWidth + 8
            body.move(to: CGPoint(x: leftX, y: topY))
            body.addQuadCurve(to: CGPoint(x: tipX, y: cy),
                               control: CGPoint(x: leftX + bodyWidth * 0.95, y: topY))
            body.addQuadCurve(to: CGPoint(x: leftX, y: botY),
                               control: CGPoint(x: leftX + bodyWidth * 0.95, y: botY))
            body.addQuadCurve(to: CGPoint(x: leftX, y: topY),
                               control: CGPoint(x: leftX + bodyWidth * 0.3, y: cy))
            body.closeSubpath()

            if kind == .xor {
                var extra = Path()
                extra.move(to: CGPoint(x: leftX - 5, y: topY))
                extra.addQuadCurve(to: CGPoint(x: leftX - 5, y: botY),
                                    control: CGPoint(x: leftX + bodyWidth * 0.2, y: cy))
                ctx.stroke(extra, with: .color(Color.primary), lineWidth: 1.6)
            }
        }
        ctx.stroke(body, with: .color(Color.primary), lineWidth: 1.8)

        var outX = tipX
        if bubble {
            let r: CGFloat = 3.2
            ctx.stroke(Path(ellipseIn: CGRect(x: tipX, y: cy - r, width: r * 2, height: r * 2)),
                       with: .color(Color.primary), lineWidth: 1.6)
            outX = tipX + r * 2
        }
        var outLead = Path()
        outLead.move(to: CGPoint(x: outX, y: cy))
        outLead.addLine(to: CGPoint(x: cx + 44, y: cy))
        ctx.stroke(outLead, with: .color(Color.primary), style: wire)
    }

    private static func drawNotGate(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat) {
        let th: CGFloat = 18
        let leftX = cx - 14, tipX = cx + 14
        var leads = Path()
        leads.move(to: CGPoint(x: cx - 44, y: cy)); leads.addLine(to: CGPoint(x: leftX, y: cy))
        ctx.stroke(leads, with: .color(Color.primary), style: wire)

        var tri = Path()
        tri.move(to: CGPoint(x: leftX, y: cy - th/2))
        tri.addLine(to: CGPoint(x: tipX, y: cy))
        tri.addLine(to: CGPoint(x: leftX, y: cy + th/2))
        tri.closeSubpath()
        ctx.stroke(tri, with: .color(Color.primary), lineWidth: 1.8)

        let r: CGFloat = 3.2
        ctx.stroke(Path(ellipseIn: CGRect(x: tipX, y: cy - r, width: r * 2, height: r * 2)),
                   with: .color(Color.primary), lineWidth: 1.6)

        var outLead = Path()
        outLead.move(to: CGPoint(x: tipX + r * 2, y: cy)); outLead.addLine(to: CGPoint(x: cx + 44, y: cy))
        ctx.stroke(outLead, with: .color(Color.primary), style: wire)
    }

    private static func drawMux(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat) {
        let leftX = cx - 16, rightX = cx + 16
        let topY = cy - 18, botY = cy + 18
        let outTopY = cy - 8, outBotY = cy + 8

        var leads = Path()
        leads.addPath(orthogonalLead(from: CGPoint(x: cx - 44, y: cy - 44), bodyEdgeX: leftX, bodyY: topY + 5))
        leads.addPath(orthogonalLead(from: CGPoint(x: cx - 44, y: cy + 44), bodyEdgeX: leftX, bodyY: botY - 5))
        leads.move(to: CGPoint(x: cx, y: cy + 44)); leads.addLine(to: CGPoint(x: cx, y: botY))
        leads.move(to: CGPoint(x: rightX, y: cy)); leads.addLine(to: CGPoint(x: cx + 44, y: cy))
        ctx.stroke(leads, with: .color(Color.primary), style: wire)

        var body = Path()
        body.move(to: CGPoint(x: leftX, y: topY))
        body.addLine(to: CGPoint(x: rightX, y: outTopY))
        body.addLine(to: CGPoint(x: rightX, y: outBotY))
        body.addLine(to: CGPoint(x: leftX, y: botY))
        body.closeSubpath()
        ctx.stroke(body, with: .color(Color.primary), lineWidth: 1.8)

        ctx.draw(Text("MUX").font(.system(size: 7, weight: .bold)).foregroundStyle(Color.primary),
                 at: CGPoint(x: cx - 1, y: cy))
        ctx.draw(Text("S").font(.system(size: 7, weight: .semibold)).foregroundStyle(Color.secondary),
                 at: CGPoint(x: cx, y: botY + 6))
    }

    private static func drawFlipFlop(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat) {
        let leftX = cx - 20, rightX = cx + 20
        let topY = cy - 30, botY = cy + 30

        var leads = Path()
        leads.addPath(orthogonalLead(from: CGPoint(x: cx - 44, y: cy - 44), bodyEdgeX: leftX, bodyY: topY + 10))
        leads.addPath(orthogonalLead(from: CGPoint(x: cx - 44, y: cy + 44), bodyEdgeX: leftX, bodyY: botY - 10))
        leads.addPath(orthogonalLead(from: CGPoint(x: cx + 44, y: cy - 44), bodyEdgeX: rightX, bodyY: topY + 10, fromLeft: false))
        leads.addPath(orthogonalLead(from: CGPoint(x: cx + 44, y: cy + 44), bodyEdgeX: rightX, bodyY: botY - 10, fromLeft: false))
        ctx.stroke(leads, with: .color(Color.primary), style: wire)

        var body = Path()
        body.addRect(CGRect(x: leftX, y: topY, width: rightX - leftX, height: botY - topY))
        ctx.stroke(body, with: .color(Color.primary), lineWidth: 1.8)

        // Clock-triangle notch at the CLK (bottom-left) pin.
        let clkY = botY - 10
        var notch = Path()
        notch.move(to: CGPoint(x: leftX, y: clkY - 5))
        notch.addLine(to: CGPoint(x: leftX + 7, y: clkY))
        notch.addLine(to: CGPoint(x: leftX, y: clkY + 5))
        ctx.stroke(notch, with: .color(Color.primary), lineWidth: 1.4)

        ctx.draw(Text("D").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.primary),
                 at: CGPoint(x: leftX + 9, y: topY + 10))
        ctx.draw(Text("Q").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.primary),
                 at: CGPoint(x: rightX - 9, y: topY + 10))
        ctx.draw(Text("Q̄").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.primary),
                 at: CGPoint(x: rightX - 9, y: botY - 10))
    }

    private static func drawClock(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ tw: CGFloat) {
        let r: CGFloat = 14
        var lead = Path()
        lead.move(to: CGPoint(x: cx + r, y: cy)); lead.addLine(to: CGPoint(x: cx + tw, y: cy))
        ctx.stroke(lead, with: .color(Color.primary), style: wire)

        var box = Path()
        box.addRoundedRect(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2), cornerSize: CGSize(width: 3, height: 3))
        ctx.stroke(box, with: .color(Color.primary), lineWidth: 1.8)

        // Mini square-wave glyph.
        var wave = Path()
        let w2 = r * 0.55
        wave.move(to: CGPoint(x: cx - w2, y: cy + w2 * 0.6))
        wave.addLine(to: CGPoint(x: cx - w2, y: cy - w2 * 0.6))
        wave.addLine(to: CGPoint(x: cx, y: cy - w2 * 0.6))
        wave.addLine(to: CGPoint(x: cx, y: cy + w2 * 0.6))
        wave.addLine(to: CGPoint(x: cx + w2, y: cy + w2 * 0.6))
        wave.addLine(to: CGPoint(x: cx + w2, y: cy - w2 * 0.6))
        ctx.stroke(wave, with: .color(Color.primary), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
    }

    /// A pin-to-body lead with a right-angle jog: horizontal from the pin,
    /// a short vertical jog, then horizontal into the body edge. Mirrors
    /// horizontally when the body is to the pin's left (`fromLeft: true`,
    /// the default — inputs) vs. to the pin's right (`fromLeft: false` —
    /// outputs on a multi-pin body like the flip-flop's Q/Q̄).
    private static func orthogonalLead(from pin: CGPoint, bodyEdgeX: CGFloat, bodyY: CGFloat,
                                       fromLeft: Bool = true) -> Path {
        let jogX = fromLeft ? bodyEdgeX - 8 : bodyEdgeX + 8
        var p = Path()
        p.move(to: pin)
        p.addLine(to: CGPoint(x: jogX, y: pin.y))
        p.addLine(to: CGPoint(x: jogX, y: bodyY))
        p.addLine(to: CGPoint(x: bodyEdgeX, y: bodyY))
        return p
    }
}
#endif
