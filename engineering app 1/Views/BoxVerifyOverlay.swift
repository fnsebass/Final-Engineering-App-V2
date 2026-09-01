#if os(iOS)
import SwiftUI

// MARK: - Phase state machine

private enum VerifyPhase: Equatable {
    case idle                   // waiting for a drag gesture
    case selecting              // drag in progress — live preview
    case ready                  // selection complete, "Analyze" button visible
    case analyzing              // waiting for Gemini response
    case result(String)         // analysis received
    case failed(String)         // error message
}

// MARK: - Main overlay view

/// Full-screen transparent view that:
///   1. Lets the user drag a selection rectangle over canvas content.
///   2. Dims everything outside the selection so the captured region is clear.
///   3. Calls `captureRegion` to get a PNG of the selection, sends it to Gemini Vision,
///      and shows the plain-text result in a floating card anchored near the box.
struct BoxVerifyOverlay: View {

    /// Parent-supplied closure that screencaps the given canvas-local rect as PNG data.
    /// Called on the main actor; may suspend briefly to wait for a clean render frame.
    let captureRegion: (CGRect) async -> Data?

    /// Called when the user wants to leave verify mode entirely.
    let onDismiss: () -> Void

    // MARK: - State

    @State private var phase: VerifyPhase = .idle

    // Drag-gesture bookkeeping
    @State private var dragAnchor: CGPoint? = nil   // set on gesture start
    @State private var dragTip: CGPoint    = .zero   // updated while dragging

    // The confirmed selection after the drag ends
    @State private var confirmedRect: CGRect? = nil

    // True while waiting for the overlay to become invisible before screenshotting.
    @State private var isCapturing = false

    // MARK: - Derived geometry

    /// Rect currently being drawn (only valid while .selecting).
    private var liveRect: CGRect? {
        guard let anchor = dragAnchor else { return nil }
        return rectFrom(anchor, dragTip)
    }

    /// The rect that should be rendered (live during drag, confirmed otherwise).
    private var renderRect: CGRect? {
        switch phase {
        case .selecting:                          return liveRect
        case .ready, .analyzing, .result, .failed: return confirmedRect
        case .idle:                               return nil
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Gesture absorber (full-screen drag target) ────────────
                gestureLayer

                // ── Dimming: dark strips around the selection ─────────────
                if let rect = renderRect, rect.width > 0 {
                    DimmingStrips(selectionRect: rect)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // ── Selection border + corner handles ─────────────────────
                if let rect = renderRect, rect.width > 16, rect.height > 16 {
                    SelectionBorder(rect: rect)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // ── Context-sensitive action panel ────────────────────────
                actionPanel(geo: geo)

                // ── "Drag to select" idle hint ────────────────────────────
                if phase == .idle { idleHint }

                // ── Dismiss button (top-right) ────────────────────────────
                dismissButton
            }
            .animation(.easeInOut(duration: 0.2), value: phase)
        }
        // Go invisible while the screenshot is being taken so the overlay
        // itself doesn't appear in the cropped image sent to Gemini.
        .opacity(isCapturing ? 0 : 1)
    }

    // MARK: - Gesture layer

    private var gestureLayer: some View {
        // near-transparent — just enough to absorb touches without obscuring content
        Color.black.opacity(0.001)
            .ignoresSafeArea()
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        if dragAnchor == nil { dragAnchor = v.startLocation }
                        dragTip = v.location
                        if phase != .selecting { phase = .selecting }
                    }
                    .onEnded { v in
                        let anchor = dragAnchor ?? v.startLocation
                        let rect   = rectFrom(anchor, v.location)
                        dragAnchor = nil
                        // Require at least 24×24 pt — prevents accidental taps
                        if rect.width > 24 && rect.height > 24 {
                            confirmedRect = rect
                            phase = .ready
                        } else {
                            phase = .idle
                        }
                    }
            )
    }

    // MARK: - Action panel (context-sensitive)

    @ViewBuilder
    private func actionPanel(geo: GeometryProxy) -> some View {
        if let rect = confirmedRect {
            switch phase {
            case .ready:
                analyzeButton(selRect: rect, geo: geo)

            case .analyzing:
                analyzingPill(selRect: rect, geo: geo)

            case .result(let text):
                resultCard(text: text, selRect: rect, geo: geo)

            case .failed(let msg):
                errorCard(msg: msg, selRect: rect, geo: geo)

            default:
                EmptyView()
            }
        }
    }

    // MARK: - Analyze button

    private func analyzeButton(selRect: CGRect, geo: GeometryProxy) -> some View {
        let pos = pillCenter(near: selRect, canvasSize: geo.size, pillHeight: 44)
        return Button {
            Task { await doAnalyze(rect: selRect) }
        } label: {
            Label("Analyze with Gemini", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20).padding(.vertical, 11)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
                .shadow(color: Color.accentColor.opacity(0.45), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .position(pos)
        .transition(.scale(scale: 0.88).combined(with: .opacity))
    }

    // MARK: - Analyzing spinner

    private func analyzingPill(selRect: CGRect, geo: GeometryProxy) -> some View {
        let pos = pillCenter(near: selRect, canvasSize: geo.size, pillHeight: 44)
        return HStack(spacing: 9) {
            ProgressView().tint(.white).scaleEffect(0.82)
            Text("Analyzing…").font(.subheadline.weight(.medium)).foregroundStyle(.white)
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
        .background(Color.accentColor.opacity(0.88), in: Capsule())
        .position(pos)
    }

    // MARK: - Result card

    private func resultCard(text: String, selRect: CGRect, geo: GeometryProxy) -> some View {
        let cardW: CGFloat = min(geo.size.width - 32, 400)
        let cardH: CGFloat = 250
        let pos = cardCenter(near: selRect, canvasSize: geo.size,
                             cardSize: CGSize(width: cardW, height: cardH))
        return VStack(alignment: .leading, spacing: 0) {
            // ── Header ──────────────────────────────────────────────────
            HStack {
                Label("Gemini Analysis", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                Spacer()
                Button { resetSelection() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary)
                        .font(.system(size: 19))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 10)

            Divider()

            // ── Body ────────────────────────────────────────────────────
            ScrollView {
                Text(text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(height: cardH - 108)

            Divider()

            // ── Footer ──────────────────────────────────────────────────
            HStack {
                Button { resetSelection() } label: {
                    Label("New Selection", systemImage: "selection.pin.in.out")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                Button { Task { await doAnalyze(rect: selRect) } } label: {
                    Label("Re-analyze", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: cardW)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.blue.opacity(0.28), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
        .position(pos)
        .transition(.scale(scale: 0.93).combined(with: .opacity))
    }

    // MARK: - Error card

    private func errorCard(msg: String, selRect: CGRect, geo: GeometryProxy) -> some View {
        let pos = cardCenter(near: selRect, canvasSize: geo.size,
                             cardSize: CGSize(width: 320, height: 130))
        return VStack(spacing: 8) {
            Label("Analysis Failed", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(msg)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineLimit(3)
            HStack(spacing: 12) {
                Button { Task { await doAnalyze(rect: selRect) } } label: {
                    Text("Retry")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                Button { resetSelection() } label: {
                    Text("Clear")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 12, y: 4)
        .position(pos)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Idle hint

    private var idleHint: some View {
        Text("Drag to draw a box around the work to verify")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(.black.opacity(0.55), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    // MARK: - Dismiss button

    private var dismissButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    ZStack {
                        Circle().fill(.black.opacity(0.42)).frame(width: 32, height: 32)
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16).padding(.top, 14)
            }
            Spacer()
        }
    }

    // MARK: - Analysis logic

    private func doAnalyze(rect: CGRect) async {
        withAnimation { phase = .analyzing }

        // Hide the overlay so it doesn't appear in the screenshot.
        // 100 ms ≈ 6 render frames at 60 fps — enough for SwiftUI to commit the
        // opacity:0 change before the window snapshot is taken.
        isCapturing = true
        try? await Task.sleep(for: .milliseconds(100))

        let capturedData = await captureRegion(rect)
        isCapturing = false     // restore overlay visibility

        do {
            guard let imageData = capturedData else { throw GeminiError.captureFailure }
            let text = try await GeminiVisionService.verify(imageData: imageData)
            withAnimation { phase = .result(text) }
        } catch {
            withAnimation { phase = .failed(error.localizedDescription) }
        }
    }

    private func resetSelection() {
        confirmedRect = nil
        withAnimation { phase = .idle }
    }

    // MARK: - Geometry helpers

    /// Builds a CGRect from two arbitrary points (order-independent).
    private func rectFrom(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Centre point for a pill/button placed below or above `selRect`, clamped to canvas.
    private func pillCenter(near selRect: CGRect, canvasSize: CGSize, pillHeight h: CGFloat) -> CGPoint {
        let pad: CGFloat = 14
        // Clamp horizontal centre so pill stays within left/right margins
        let cx = max(90, min(selRect.midX, canvasSize.width - 90))
        if selRect.maxY + pad + h < canvasSize.height - 16 {
            return CGPoint(x: cx, y: selRect.maxY + pad + h / 2)   // below
        }
        if selRect.minY - pad - h > 16 {
            return CGPoint(x: cx, y: selRect.minY - pad - h / 2)   // above
        }
        return CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2) // fallback
    }

    /// Centre point for a floating card placed below or above `selRect`, clamped to canvas.
    private func cardCenter(near selRect: CGRect, canvasSize: CGSize, cardSize: CGSize) -> CGPoint {
        let pad: CGFloat = 14
        let halfW = cardSize.width  / 2
        let halfH = cardSize.height / 2
        let cx    = max(halfW + 8, min(selRect.midX, canvasSize.width - halfW - 8))
        if selRect.maxY + pad + cardSize.height < canvasSize.height - 16 {
            return CGPoint(x: cx, y: selRect.maxY + pad + halfH)    // below
        }
        if selRect.minY - pad - cardSize.height > 16 {
            return CGPoint(x: cx, y: selRect.minY - pad - halfH)    // above
        }
        return CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    }
}

// MARK: - Dimming strips

/// Renders a dark overlay around `selectionRect` using four rectangles (top, bottom, left, right).
/// This avoids blend-mode tricks, making it reliable across all iOS targets.
private struct DimmingStrips: View {
    let selectionRect: CGRect

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r = selectionRect

            Canvas { ctx, _ in
                let shade = GraphicsContext.Shading.color(.black.opacity(0.45))
                //  ┌────────────────────────────────┐
                //  │             top                │
                //  ├──────┬─────────────────┬───────┤
                //  │ left │   SELECTION     │ right │
                //  ├──────┴─────────────────┴───────┤
                //  │            bottom              │
                //  └────────────────────────────────┘
                let top    = CGRect(x: 0,      y: 0,      width: w,              height: max(0, r.minY))
                let bottom = CGRect(x: 0,      y: r.maxY, width: w,              height: max(0, h - r.maxY))
                let left   = CGRect(x: 0,      y: r.minY, width: max(0, r.minX), height: r.height)
                let right  = CGRect(x: r.maxX, y: r.minY, width: max(0, w - r.maxX), height: r.height)
                for strip in [top, bottom, left, right] { ctx.fill(Path(strip), with: shade) }
            }
        }
    }
}

// MARK: - Marching-ants selection border

/// Animated dashed rectangle with solid corner handles drawn directly on a Canvas.
private struct SelectionBorder: View {
    let rect: CGRect
    @State private var dashPhase: CGFloat = 0

    var body: some View {
        Canvas { ctx, _ in
            let style = StrokeStyle(lineWidth: 1.5, dash: [8, 5], dashPhase: dashPhase)
            let shadow = StrokeStyle(lineWidth: 2.5, dash: [8, 5], dashPhase: dashPhase)

            // Dark shadow stroke for contrast on any background colour
            ctx.stroke(Path(rect.insetBy(dx: -0.5, dy: -0.5)),
                       with: .color(.black.opacity(0.35)), style: shadow)

            // White marching-ants
            ctx.stroke(Path(rect), with: .color(.white), style: style)

            // Corner handles — solid L-shapes, 12 pt arms, 2.5 pt line
            for (origin, dx, dy) in cornerSpecs(rect) {
                var p = Path()
                p.move(to: CGPoint(x: origin.x + dx * 12, y: origin.y))
                p.addLine(to: origin)
                p.addLine(to: CGPoint(x: origin.x, y: origin.y + dy * 12))
                ctx.stroke(p, with: .color(.white),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .square))
            }
        }
        .ignoresSafeArea()
        // Animate dashPhase so the ants appear to march along the border.
        .onAppear {
            withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                dashPhase -= 13   // one full dash-gap cycle = 8 + 5 = 13 pt
            }
        }
    }

    /// Returns (cornerPoint, xDirection, yDirection) for all four corners.
    /// Direction values are ±1 so the arm points outward from the corner.
    private func cornerSpecs(_ r: CGRect) -> [(CGPoint, CGFloat, CGFloat)] {
        [
            (CGPoint(x: r.minX, y: r.minY), +1, +1),   // top-left
            (CGPoint(x: r.maxX, y: r.minY), -1, +1),   // top-right
            (CGPoint(x: r.minX, y: r.maxY), +1, -1),   // bottom-left
            (CGPoint(x: r.maxX, y: r.maxY), -1, -1),   // bottom-right
        ]
    }
}
#endif
