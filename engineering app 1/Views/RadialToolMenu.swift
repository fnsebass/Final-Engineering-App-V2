//
//  RadialToolMenu.swift
//  Tolerance
//
//  A tool/color palette arranged along a translucent grey tube that traces
//  a tight 90pt-radius arc centered on the Apple Pencil's tip, shown as a
//  floating overlay anchored to the Pencil's current or last-known
//  position. See CanvasWorkspace.handleShowToolPalette for how the anchor
//  point is resolved and this view is positioned.
//
//  In SwiftUI's y-down screen convention, the arc runs 170°-280° (180°
//  points straight left from the pivot/anchor — the negative x-axis; 270°
//  points straight up — the positive y-axis; this stretches 10° past each
//  of those for a wider, 110° sweep). It's split down the middle:
//    • First half  (170°-225°) — Eraser, Highlighter, Straight Line, Shape.
//      Each is a bare icon with no background; only the currently active
//      tool gets a faint circle behind it.
//    • Second half (225°-280°) — ink colors, rendered as the same style of
//      icon as the first half (a tinted circle glyph, not a big solid dot),
//      dragged like a rotary dial. Every color's position slides smoothly
//      and continuously as you drag rather than snapping between slots.
//

import SwiftUI

struct RadialToolMenu: View {
    let activeTool: DrawingTool
    var onSelectTool: (DrawingTool) -> Void
    var onSelectColor: (Color) -> Void

    /// A broad, saturated swatch set — separate from the 5 persisted pencil
    /// slots, since this palette is meant to offer many more colors than those.
    static let colorPalette: [Color] = [
        .black, Color(white: 0.45), .white,
        .red, .orange, .yellow, .green, .mint, .teal, .cyan,
        .blue, .indigo, .purple, .pink, .brown,
        Color(red: 0.55, green: 0.02, blue: 0.02),  // deep red
        Color(red: 0.85, green: 0.55, blue: 0.10),  // amber
        Color(red: 0.05, green: 0.35, blue: 0.15),  // deep green
        Color(red: 0.05, green: 0.15, blue: 0.45),  // navy
        Color(red: 0.40, green: 0.20, blue: 0.05),  // dark brown
    ]

    // MARK: - Geometry (static — pure constants, so callers can position
    // this view without needing an instance).

    /// Distance from the Pencil tip — unchanged from the last pass.
    static let radius: CGFloat = 90
    /// Extra breathing room beyond `radius` so icons/dots near the arc's
    /// outer edge aren't clipped by this view's own frame.
    static let margin: CGFloat = 40
    static let sideLength: CGFloat = radius + margin

    /// 110° sweep (up from a plain 90° quarter circle) — 10° past the
    /// negative x-axis and 10° past the positive y-axis on each end.
    private static let startAngle: Double = 170
    private static let splitAngle: Double = 225
    private static let endAngle: Double = 280
    private static let visibleColorSlots = 3

    private static let toolIconSize: CGFloat = 15
    private static let toolHighlightDiameter: CGFloat = 30
    private static let hitRegionWidth: CGFloat = 40
    /// Thickness of the translucent grey tube the icons sit on top of.
    private static let tubeWidth: CGFloat = toolHighlightDiameter + 12

    /// The pivot — where the Pencil anchor point sits — is fixed at this
    /// view's bottom-right corner; the arc bows up and to the left from there.
    private static var pivot: CGPoint { CGPoint(x: sideLength, y: sideLength) }

    /// Where to `.position()` this view so its pivot lands exactly on `anchor`.
    static func frameCenter(forAnchor anchor: CGPoint) -> CGPoint {
        CGPoint(x: anchor.x - sideLength / 2, y: anchor.y - sideLength / 2)
    }

    @State private var committedOffset: Double = 0
    @GestureState private var dragAngleDelta: Double = 0

    private var colorSlotStep: Double { (Self.endAngle - Self.splitAngle) / Double(Self.visibleColorSlots) }
    private var maxOffset: Double { Double(max(Self.colorPalette.count - Self.visibleColorSlots, 0)) }
    private var liveOffset: Double {
        (committedOffset + dragAngleDelta / colorSlotStep).clamped(to: 0...maxOffset)
    }

    var body: some View {
        ZStack {
            // A translucent grey tube the buttons sit on top of, rather
            // than bare floating icons.
            arcPath(from: Self.startAngle, to: Self.endAngle)
                .stroke(Color(white: 0.5).opacity(0.38), style: StrokeStyle(lineWidth: Self.tubeWidth, lineCap: .round))
            arcPath(from: Self.startAngle, to: Self.endAngle)
                .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, lineCap: .round))

            // Invisible wide hit-region so a drag started anywhere along the
            // bottom half (not just directly on a dot) scrolls the colors.
            arcPath(from: Self.splitAngle, to: Self.endAngle)
                .stroke(Color.clear, style: StrokeStyle(lineWidth: Self.hitRegionWidth, lineCap: .round))
                .contentShape(
                    .interaction,
                    arcPath(from: Self.splitAngle, to: Self.endAngle)
                        .stroke(style: StrokeStyle(lineWidth: Self.hitRegionWidth, lineCap: .round))
                )
                .gesture(colorScrollGesture)

            ForEach(Array(toolItems.enumerated()), id: \.offset) { i, item in
                let angle = angleFor(index: i, count: toolItems.count, from: Self.startAngle, to: Self.splitAngle)
                toolKnob(item.systemImage, isActive: activeTool == item.tool) { onSelectTool(item.tool) }
                    .position(point(at: angle, radius: Self.radius))
            }

            // Every color gets its own continuously-interpolated slot
            // position (not a fixed slot with its content swapped), so
            // dragging slides colors smoothly along the arc instead of
            // jumping from one to the next.
            ForEach(Array(Self.colorPalette.enumerated()), id: \.offset) { idx, color in
                let slotPos = Double(idx) - liveOffset
                if slotPos > -1.3 && slotPos < Double(Self.visibleColorSlots) + 0.3 {
                    let angle = Self.splitAngle + colorSlotStep * (slotPos + 0.5)
                    colorKnob(color) { onSelectColor(color) }
                        .opacity(edgeFade(for: slotPos))
                        .position(point(at: angle, radius: Self.radius))
                }
            }
        }
        .frame(width: Self.sideLength, height: Self.sideLength)
    }

    /// Smoothly fades a color glyph out as it slides past either edge of
    /// the visible window, instead of it popping in/out abruptly.
    private func edgeFade(for slotPos: Double) -> Double {
        let fadeZone = 0.7
        if slotPos < 0 { return (1 + slotPos / fadeZone).clamped(to: 0...1) }
        let over = slotPos - (Double(Self.visibleColorSlots) - 1)
        if over > 0 { return (1 - over / fadeZone).clamped(to: 0...1) }
        return 1
    }

    // MARK: - Tool items

    private let toolItems: [(tool: DrawingTool, systemImage: String)] = [
        (.eraser, "eraser"),
        (.highlighter, "highlighter"),
        (.straightLine, "line.diagonal"),
        (.shape, "square.on.circle"),
    ]

    // MARK: - Gestures

    private var colorScrollGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($dragAngleDelta) { value, state, _ in
                state = angleDegrees(for: value.location) - angleDegrees(for: value.startLocation)
            }
            .onEnded { value in
                let delta = angleDegrees(for: value.location) - angleDegrees(for: value.startLocation)
                committedOffset = (committedOffset + delta / colorSlotStep).clamped(to: 0...maxOffset)
            }
    }

    private func angleDegrees(for pt: CGPoint) -> Double {
        let dx = pt.x - Self.pivot.x, dy = pt.y - Self.pivot.y
        var deg = atan2(dy, dx) * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }

    // MARK: - Geometry helpers

    private func arcPath(from: Double, to: Double) -> Path {
        Path { p in
            p.addArc(center: Self.pivot, radius: Self.radius,
                     startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
        }
    }

    private func angleFor(index: Int, count: Int, from: Double, to: Double) -> Double {
        from + (to - from) * (Double(index) + 0.5) / Double(count)
    }

    private func point(at degrees: Double, radius: CGFloat) -> CGPoint {
        let rad = Angle(degrees: degrees).radians
        return CGPoint(x: Self.pivot.x + radius * CGFloat(cos(rad)),
                        y: Self.pivot.y + radius * CGFloat(sin(rad)))
    }

    // MARK: - Content

    private func toolKnob(_ systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        paletteIcon(systemImage, tint: .primary, isActive: isActive, action: action)
    }

    /// Colors use the same bare-icon treatment as the tools above — a
    /// tinted glyph, not a big solid dot — via the same "circle.fill" symbol.
    private func colorKnob(_ color: Color, action: @escaping () -> Void) -> some View {
        paletteIcon("circle.fill", tint: color, isActive: false, action: action)
    }

    private func paletteIcon(_ systemImage: String, tint: Color, isActive: Bool, action: @escaping () -> Void) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: Self.toolIconSize, weight: .semibold))
            .foregroundStyle(isActive ? Color.accentColor : tint)
            .frame(width: Self.toolHighlightDiameter, height: Self.toolHighlightDiameter)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear, in: Circle())
            .shadow(color: .black.opacity(isActive ? 0 : 0.25), radius: 1.5)
            .contentShape(Circle())
            .onTapGesture(perform: action)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
