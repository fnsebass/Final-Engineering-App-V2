//
//  CanvasWorkspace.swift
//  Tolerance
//
//  Hosts one notepad's infinite-scroll canvas. Manages:
//    • The canvas + paper theme
//    • Double-tap quick-action menu → graph / chemistry / AI, straight from
//      OCR + stored corrections to the AI call (no confirmation step).
//    • Live equation checking: ~1s after the user pauses, the last-written
//      region is OCR'd and algebra-checked automatically; a check/X badge
//      appears near it, tappable for the full floating AIResultPanel.
//    • Ruler overlay
//    • Graph: floating card (drag header to move, top-left handle to resize)
//      Quick Graph type-in and history live in the notebook side panel's
//      Graphs tab, which requests a plot here via `requestedGraph`.
//    • Photo import, placement, resize, and rotation
//    • Apple Pencil squeeze-to-erase
//
//  activeTool / penColor / rulerActive come in as bindings from the parent.
//  iOS/iPadOS only.
//

#if os(iOS)
import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Live-check badge

private struct LiveCheckBadge {
    enum Status { case checking, correct, incorrect }
    /// Top-left corner of the equation this badge is checking.
    let anchor: CGPoint
    var status: Status
    var recognizedText: String = ""
}

/// Deliberately muted rather than a bright/saturated green or red, matching
/// the rest of the app's duller accent palette.
private let liveCheckGreen = Color(red: 0.42, green: 0.62, blue: 0.44)
private let liveCheckRed   = Color(red: 0.72, green: 0.36, blue: 0.34)

/// A faint ring that traces the outline of a circle while a live check is
/// running, replacing the platform's default dotted/segmented spinner.
private struct RingSpinner: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 18, height: 18)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - CanvasWorkspace

struct CanvasWorkspace: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var notepad: Notepad

    @Binding var activeTool: DrawingTool
    @Binding var penColor: Color
    @Binding var rulerActive: Bool
    @Binding var isVerifyMode: Bool
    @Binding var showPhotoPicker: Bool
    let activeShapeKind: ShapeKind
    var onUndoManagerReady: (UndoManager?) -> Void = { _ in }
    /// Set (momentarily, by the notebook side panel's Graphs tab) to reopen a
    /// previously-plotted expression. Not a Binding — the caller resets it to
    /// nil right after setting it, so re-tapping the same history row still
    /// triggers `.onChange` below.
    var requestedGraph: String? = nil
    /// Paired with `requestedGraph` — nil = auto-detect, true/false forces the mode.
    var requestedGraphForce3D: Bool? = nil

    // Stored handwriting corrections (applied automatically before every action)
    @Query(sort: \HandwritingCorrection.useCount, order: .reverse)
    private var storedCorrections: [HandwritingCorrection]

    // Double-tap quick-action menu overlay
    @State private var menuPos: CGPoint? = nil
    // Anchor for the floating AIResultPanel — set alongside menuPos but not
    // cleared when the quick-action menu is dismissed, since the panel opens
    // after the menu (and its underlying pill) has already gone away.
    @State private var panelAnchor: CGPoint = CGPoint(x: 200, y: 200)
    @State private var menuImage: UIImage? = nil

    // Side panel
    @State private var showPanel = false
    @State private var panelMode: PanelMode = .explain
    @State private var recognizedText: String = ""
    @State private var unitResult: UnitCheckResult? = nil
    @State private var numericResult: NumericCheckResult? = nil
    @State private var algebraicResult: AlgebraicCheckResult? = nil
    @State private var stepReview: StepReviewResult? = nil
    @State private var explanation: AIReviewResult? = nil
    @State private var chemistryResult: ChemistryResult? = nil
    @State private var isAnalyzing = false

    // Ruler
    @State private var rulerY: CGFloat = 300

    // Graph — OCR/disambiguation
    @State private var showGraph = false
    @State private var graphEquationText: String = ""
    @State private var graphExpression: String = ""
    @State private var graphForce3D: Bool? = nil
    @State private var showGraphModeChoice = false
    @State private var pendingGraphImage: UIImage? = nil

    // Graph — floating card position & size
    @State private var graphCardCenter: CGPoint? = nil
    @State private var graphCardWidth: CGFloat = 540

    // Changing this forces PencilCanvasView to fully tear down and rebuild
    // its PKCanvasView — see the "zombie canvas" fix in canvasViewDrawingDidChange.
    @State private var canvasResetToken = UUID()

    // Photos
    @State private var selectedPhotoID: PersistentIdentifier? = nil
    @State private var pendingPhotoItems: [PhotosPickerItem] = []

    // Pencil squeeze-to-erase state
    @State private var toolBeforeErase: DrawingTool? = nil

    // Pen Buttons "Switch Colors" action reuses the same 5-slot pencil
    // palette NotepadEditorView's header shows, so both stay in sync.
    @AppStorage("selectedPencilSlot") private var selectedColorTag: Int = 0
    @AppStorage("pencilSlot0") private var pencilHex0: String = "#262626"
    @AppStorage("pencilSlot1") private var pencilHex1: String = "#173B9E"
    @AppStorage("pencilSlot2") private var pencilHex2: String = "#D48008"
    @AppStorage("pencilSlot3") private var pencilHex3: String = "#127038"
    @AppStorage("pencilSlot4") private var pencilHex4: String = "#BD1414"

    // Radial tool/color palette (Settings → Pen Buttons → "Show Tool Palette",
    // the squeeze default) — anchored to the Pencil's current/last position.
    @State private var radialPaletteAnchor: CGPoint? = nil

    // Live equation-check badge
    @State private var liveCheckBadge: LiveCheckBadge? = nil
    /// Bumped on every new check request so a slow, stale request can't
    /// overwrite the badge for a check that started after it.
    @State private var liveCheckGeneration = 0

    /// Tracks the workspace's own size so the floating AIResultPanel's drag
    /// handler can clamp its position without needing a GeometryReader of its own.
    @State private var workspaceSize: CGSize = .zero

    private let reviewService: any EquationReviewService = OnDeviceEquationReviewService()

    // Settings → Intelligence → Tutor Interactions: off gives a brief answer
    // check (reviewService.review) instead of a full step-by-step walkthrough
    // (reviewService.explain).
    @AppStorage(LayoutPrefs.aiVerbose) private var aiVerbose = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Canvas ────────────────────────────────────────────────
                if let page = notepad.orderedPages.first {
                    PencilCanvasView(
                        page: page,
                        paperColorHex: notepad.paperColorHex,
                        paperStyle: notepad.paperStyle,
                        gridColumns: notepad.gridColumns,
                        activeTool: $activeTool,
                        penColor: $penColor,
                        penWidth: 3,
                        activeShapeKind: activeShapeKind,
                        onDoubleTapMenu: { pos, image in
                            menuImage = image
                            menuPos = clamped(pos, in: geo.size)
                            panelAnchor = clamped(pos, in: geo.size, boxSize: CGSize(width: 420, height: 520))
                        },
                        onLiveCheckRegion: { pos, image in
                            handleLiveCheck(at: pos, image: image)
                        },
                        onPencilSqueezeBegan: handleSqueezeBegan,
                        onPencilSqueezeEnded: handleSqueezeEnded,
                        onRequestTool: handleRequestTool,
                        onSwitchColor: handleSwitchColor,
                        onShowToolPalette: handleShowToolPalette,
                        onUndoManagerReady: onUndoManagerReady,
                        onNeedsRecreate: { canvasResetToken = UUID() }
                    )
                    .id(canvasResetToken)
                    .ignoresSafeArea(.container, edges: .bottom)

                    // ── Photo layer (above canvas, below other overlays) ─
                    photoLayer(for: page)
                        .zIndex(1)
                } else {
                    ProgressView("Preparing…").onAppear(perform: ensurePage)
                }

                // ── Context menu ──────────────────────────────────────────
                if menuPos != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation { menuPos = nil; menuImage = nil } }
                        .zIndex(9)
                }

                if let pos = menuPos {
                    QuickActionMenu(
                        onGraph:      handleGraph,
                        onChemistry:  handleChemistry,
                        onAI:         handleAI
                    )
                    .position(pos)
                    .zIndex(10)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                // ── Radial tool/color palette (Pencil squeeze) ────────────
                if radialPaletteAnchor != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { radialPaletteAnchor = nil }
                        .zIndex(9)
                }

                if let anchor = radialPaletteAnchor {
                    RadialToolMenu(
                        activeTool: activeTool,
                        onSelectTool: applyRadialTool,
                        onSelectColor: applyRadialColor
                    )
                    .position(RadialToolMenu.frameCenter(forAnchor: anchor))
                    .zIndex(10)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                // ── Ruler ─────────────────────────────────────────────────
                if rulerActive {
                    RulerBar()
                        .frame(width: geo.size.width)
                        .position(x: geo.size.width / 2, y: rulerY)
                        .gesture(DragGesture().onChanged { v in
                            rulerY = max(10, min(geo.size.height - 10, v.location.y))
                        })
                        .zIndex(5)
                }

                // ── Floating graph card ─────────────────────────────────────
                // Quick Graph's type-in field and history now live in the
                // notebook side panel's Graphs tab (see ChapterSidebarView);
                // every graph shown here is already recorded there, so
                // there's no separate "pin" action anymore.
                if showGraph, let center = graphCardCenter {
                    EquationGraphView(
                        equationText: graphEquationText,
                        expression: graphExpression,
                        forceIs3D: graphForce3D,
                        isPresented: $showGraph,
                        onHeaderDrag: { delta in
                            let oldCenter = graphCardCenter ?? center
                            let hw = graphCardWidth / 2
                            let newX = (oldCenter.x + delta.width).clamped(to: hw ... geo.size.width - hw)
                            let newY = (oldCenter.y + delta.height).clamped(to: 60 ... geo.size.height - 60)
                            graphCardCenter = CGPoint(x: newX, y: newY)
                        },
                        onTopLeftResize: { delta in
                            // Right edge stays fixed; left edge moves → width changes
                            let newW = max(300, graphCardWidth - delta.width)
                            let dw   = graphCardWidth - newW
                            graphCardWidth = newW
                            // Center shifts right by half the width lost
                            if let c = graphCardCenter {
                                let newX = (c.x + dw / 2).clamped(to: newW / 2 ... geo.size.width - newW / 2)
                                graphCardCenter = CGPoint(x: newX, y: c.y)
                            }
                        }
                    )
                    .frame(width: graphCardWidth)
                    .position(center)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(8)
                }

                // ── Live equation-check badge — always top-left of the equation ──
                if let badge = liveCheckBadge {
                    Group {
                        switch badge.status {
                        case .checking:
                            RingSpinner()
                        case .correct:
                            Button { openCheckPanel(for: badge, in: geo.size) } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(liveCheckGreen)
                            }
                            .buttonStyle(.plain)
                        case .incorrect:
                            Button { openCheckPanel(for: badge, in: geo.size) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(liveCheckRed)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .position(x: badge.anchor.x - 8, y: badge.anchor.y - 8)
                    .zIndex(7)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                // ── Box-to-Verify overlay (Gemini Vision) ─────────────────────────
                if isVerifyMode {
                    let globalOrigin = geo.frame(in: .global).origin
                    BoxVerifyOverlay(
                        captureRegion: { rect in
                            // Run on the main thread — UIKit rendering APIs require this.
                            await MainActor.run { [globalOrigin] in
                                guard let scene = UIApplication.shared.connectedScenes
                                    .first as? UIWindowScene,
                                    let window = scene.windows.first(where: { $0.isKeyWindow })
                                              ?? scene.windows.first else { return nil }

                                let scale = window.screen.scale
                                let renderer = UIGraphicsImageRenderer(bounds: window.bounds)

                                // afterScreenUpdates: false — captures the most recently
                                // committed frame. BoxVerifyOverlay set itself opacity:0
                                // 100 ms ago, so this frame shows clean canvas content.
                                let full = renderer.image { _ in
                                    window.drawHierarchy(in: window.bounds,
                                                         afterScreenUpdates: false)
                                }

                                // Convert canvas-local selection rect → window pixel rect.
                                // globalOrigin: canvas origin in global (window) coordinates.
                                // rect:         selection in canvas-local points.
                                // Multiply by scale to get physical pixel coordinates.
                                let pixelRect = CGRect(
                                    x: (globalOrigin.x + rect.minX) * scale,
                                    y: (globalOrigin.y + rect.minY) * scale,
                                    width:  rect.width  * scale,
                                    height: rect.height * scale
                                )

                                guard pixelRect.width > 4, pixelRect.height > 4,
                                      let cropped = full.cgImage?.cropping(to: pixelRect)
                                else { return nil }

                                return UIImage(cgImage: cropped,
                                              scale: scale, orientation: .up).pngData()
                            }
                        },
                        onDismiss: { isVerifyMode = false }
                    )
                    .ignoresSafeArea()
                    .zIndex(18)
                    .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: menuPos != nil)
            .animation(.easeInOut(duration: 0.28), value: showGraph)
            .photosPicker(isPresented: $showPhotoPicker,
                          selection: $pendingPhotoItems,
                          maxSelectionCount: 5,
                          matching: .images)
            .onChange(of: pendingPhotoItems) { _, items in
                Task { await importPhotos(items, canvasSize: geo.size) }
            }
            .onChange(of: requestedGraph) { _, expr in
                guard let expr else { return }
                // Strips a "z =" / "y =" / "f(x,y) =" prefix (typed via Quick
                // Graph's new z/y keys) so the evaluator only ever sees the
                // bare right-hand side.
                graphEquationText = expr
                graphExpression = MathEvaluator.extractExpression(from: expr) ?? expr
                graphForce3D = requestedGraphForce3D
                recordGraphHistory(expr)
                withAnimation { showGraph = true }
            }
            .confirmationDialog("Plot as…", isPresented: $showGraphModeChoice, titleVisibility: .visible) {
                Button("2-D  (y = f(x))")    { startGraph(force3D: false) }
                Button("3-D  (z = f(x,y))") { startGraph(force3D: true) }
                Button("Auto-Detect")        { startGraph(force3D: nil) }
                Button("Cancel", role: .cancel) { pendingGraphImage = nil }
            } message: {
                Text("Choose how to plot this expression")
            }
            .onChange(of: showGraph) { _, show in
                if show && graphCardCenter == nil {
                    graphCardCenter = CGPoint(
                        x: geo.size.width / 2,
                        y: geo.size.height - 260
                    )
                    graphCardWidth = min(540, geo.size.width - 32)
                }
                if !show {
                    graphCardCenter = nil
                }
            }
            .onAppear { workspaceSize = geo.size }
            .onChange(of: geo.size) { _, newSize in workspaceSize = newSize }
        }
        .overlay {
            if showPanel {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { showPanel = false; isAnalyzing = false; resetPanelState() }
                    .zIndex(11)
            }
        }
        .overlay {
            if showPanel {
                AIResultPanel(
                    recognizedText: $recognizedText,
                    mode: panelMode,
                    unitResult: unitResult,
                    numericResult: numericResult,
                    algebraicResult: algebraicResult,
                    stepReview: stepReview,
                    explanation: explanation,
                    chemistryResult: chemistryResult,
                    isAnalyzing: isAnalyzing,
                    onRerun: rerunAnalysis,
                    onClose: { showPanel = false; isAnalyzing = false; resetPanelState() },
                    onDrag: dragPanel
                )
                .position(panelAnchor)
                .zIndex(12)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .onAppear(perform: ensurePage)
    }

    // MARK: - Photo layer

    @ViewBuilder
    private func photoLayer(for page: Page) -> some View {
        ForEach(page.photos) { photo in
            let pid = photo.id
            PhotoCardView(
                photo: photo,
                isSelected: selectedPhotoID == pid,
                onSelect: { selectedPhotoID = selectedPhotoID == pid ? nil : pid },
                onDelete: { selectedPhotoID = nil; modelContext.delete(photo) }
            )
        }
    }

    // MARK: - Pencil squeeze-to-erase

    private func handleSqueezeBegan() {
        guard activeTool != .eraser else { return }
        toolBeforeErase = activeTool
        activeTool = .eraser
    }

    private func handleSqueezeEnded() {
        if let prev = toolBeforeErase {
            activeTool = prev
            toolBeforeErase = nil
        }
    }

    // MARK: - Pen Buttons "Switch Colors" / "Trigger Lasso" actions

    private func handleRequestTool(_ tool: DrawingTool) {
        activeTool = tool
    }

    private func handleSwitchColor() {
        selectedColorTag = (selectedColorTag + 1) % 5
        let hexes = [pencilHex0, pencilHex1, pencilHex2, pencilHex3, pencilHex4]
        penColor = PaperTheme.color(fromHex: hexes[selectedColorTag])
        if activeTool == .eraser || activeTool == .lasso { activeTool = .pen }
    }

    // MARK: - Radial tool/color palette (Pencil squeeze)

    /// `pos` is in canvas view-space (already converted from content-space
    /// by PencilCanvasView). Clamped so the arc — which bows down-left from
    /// this anchor — always stays fully on-screen. Toggles: squeezing again
    /// while the palette is already showing dismisses it instead of moving it.
    private func handleShowToolPalette(at pos: CGPoint) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            if radialPaletteAnchor != nil {
                radialPaletteAnchor = nil
            } else {
                // The arc now bows up and to the left from the anchor, so it
                // needs room to the left (as before) and above (not below).
                let pad = RadialToolMenu.radius + 24
                let x = pos.x.clamped(to: pad...max(pad, workspaceSize.width - 8))
                let y = pos.y.clamped(to: pad...max(pad, workspaceSize.height - 8))
                radialPaletteAnchor = CGPoint(x: x, y: y)
            }
        }
    }

    private func applyRadialTool(_ tool: DrawingTool) {
        activeTool = tool
        radialPaletteAnchor = nil
    }

    private func applyRadialColor(_ color: Color) {
        setPencilHex(PaperTheme.hex(from: color), at: selectedColorTag)
        penColor = color
        if activeTool == .eraser || activeTool == .lasso { activeTool = .pen }
        radialPaletteAnchor = nil
    }

    private func setPencilHex(_ hex: String, at i: Int) {
        switch i {
        case 0: pencilHex0 = hex
        case 1: pencilHex1 = hex
        case 2: pencilHex2 = hex
        case 3: pencilHex3 = hex
        case 4: pencilHex4 = hex
        default: break
        }
    }

    // MARK: - Helpers

    private func clamped(_ pos: CGPoint, in size: CGSize, boxSize: CGSize = CGSize(width: 380, height: 72)) -> CGPoint {
        let w = boxSize.width, h = boxSize.height
        return CGPoint(
            x: min(max(pos.x, w / 2 + 12), size.width  - w / 2 - 12),
            y: min(max(pos.y - 50, h / 2 + 12), size.height - h / 2 - 12)
        )
    }

    /// Lets the user drag the floating AIResultPanel anywhere on the workspace,
    /// clamped so its grabber stays reachable near the edges.
    private func dragPanel(by delta: CGSize) {
        let halfW: CGFloat = 210, halfH: CGFloat = 260
        let maxX = max(halfW, workspaceSize.width - halfW)
        let maxY = max(halfH, workspaceSize.height - halfH)
        panelAnchor = CGPoint(
            x: (panelAnchor.x + delta.width).clamped(to: halfW...maxX),
            y: (panelAnchor.y + delta.height).clamped(to: halfH...maxY)
        )
    }

    private func ensurePage() {
        guard notepad.orderedPages.isEmpty else { return }
        let page = Page(pageIndex: 0)
        page.notepad = notepad
        modelContext.insert(page)
    }

    // MARK: - Stored-correction application

    private func applyStoredCorrections(_ text: String) -> String {
        var result = text
        for c in storedCorrections where result.contains(c.ocrFragment) {
            result = result.replacingOccurrences(of: c.ocrFragment, with: c.correctedFragment)
            c.useCount += 1
        }
        return result
    }

    // MARK: - Quick-action handlers (double-tap menu — straight to the AI call)

    private func handleGraph() {
        guard let image = menuImage else { menuPos = nil; return }
        menuPos = nil; menuImage = nil
        pendingGraphImage = image
        showGraphModeChoice = true
    }

    private func startGraph(force3D: Bool?) {
        guard let image = pendingGraphImage else { return }
        pendingGraphImage = nil
        graphForce3D = force3D
        Task {
            let rawOCR    = await EquationOCR.recognize(in: image)
            let corrected = applyStoredCorrections(rawOCR)
            await continueGraph(with: corrected)
        }
    }

    private func continueGraph(with text: String) async {
        let aiExpr = await reviewService.extractGraphExpression(from: text)
        let expr   = aiExpr ?? MathEvaluator.extractExpression(from: text) ?? text
        graphEquationText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        graphExpression   = expr
        recordGraphHistory(expr)
        withAnimation { showGraph = true }
    }

    /// Appends `expr` to this note's graph history (skipping consecutive
    /// duplicates), surfaced in the notebook side panel's Graphs tab.
    private func recordGraphHistory(_ expr: String) {
        let trimmed = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, notepad.graphHistory.last != trimmed else { return }
        notepad.graphHistory.append(trimmed)
    }


    private func handleChemistry() {
        guard let image = menuImage else { menuPos = nil; return }
        menuPos = nil; menuImage = nil
        panelMode = .chemistry
        showPanel = true
        isAnalyzing = true
        resetPanelState()
        Task {
            let rawOCR    = await EquationOCR.recognize(in: image)
            let corrected = applyStoredCorrections(rawOCR)
            await continueChemistry(with: corrected)
        }
    }

    private func continueChemistry(with text: String) async {
        recognizedText = text
        let result = await reviewService.analyzeChemistry(problem: text)
        chemistryResult = result
        isAnalyzing = false
    }

    // MARK: - Live equation checking

    /// Called by PencilCanvasView ~1s after the user stops writing near
    /// `pos`. OCR's that region and shows a check/X badge — no confirmation
    /// step, since this runs silently in the background rather than
    /// interrupting the user like the double-tap menu actions do.
    private func handleLiveCheck(at pos: CGPoint, image: UIImage) {
        liveCheckGeneration += 1
        let generation = liveCheckGeneration
        withAnimation(.easeIn(duration: 0.15)) {
            liveCheckBadge = LiveCheckBadge(anchor: pos, status: .checking)
        }
        Task {
            let rawOCR = await EquationOCR.recognize(in: image)
            let corrected = applyStoredCorrections(rawOCR)
            guard generation == liveCheckGeneration else { return }
            guard !corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                withAnimation { liveCheckBadge = nil }
                return
            }
            let result = await reviewService.checkAlgebra(problem: corrected)
            guard generation == liveCheckGeneration else { return }
            let status: LiveCheckBadge.Status
            switch result.state {
            case .correct:   status = .correct
            case .hasErrors: status = .incorrect
            case .modelUnavailable, .skipped, .failed:
                withAnimation { liveCheckBadge = nil }
                return
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                liveCheckBadge = LiveCheckBadge(anchor: pos, status: status, recognizedText: corrected)
            }
        }
    }

    /// Tapping a live-check badge opens the full floating panel for a deeper look.
    private func openCheckPanel(for badge: LiveCheckBadge, in size: CGSize) {
        liveCheckBadge = nil
        panelMode = .check
        showPanel = true
        isAnalyzing = true
        resetPanelState()
        panelAnchor = clamped(badge.anchor, in: size, boxSize: CGSize(width: 420, height: 520))
        Task { await continueCheck(with: badge.recognizedText) }
    }

    private func continueCheck(with text: String) async {
        recognizedText = text
        async let algebraTask = reviewService.checkAlgebra(problem: text)
        let dimR = UnitChecker.check(text)
        let numR = UnitChecker.checkNumeric(text)
        let algR = await algebraTask
        unitResult      = dimR
        numericResult   = numR
        algebraicResult = algR
        isAnalyzing     = false
    }

    private func handleAI() {
        guard let image = menuImage else { menuPos = nil; return }
        menuPos = nil; menuImage = nil

        // Send the long-press screenshot directly to Gemini Vision —
        // no OCR step needed, the model reads the image directly.
        guard let imageData = image.pngData() else { return }
        panelMode = .explain
        showPanel = true
        isAnalyzing = true
        resetPanelState()
        recognizedText = "Analyzing with Gemini Vision…"
        Task {
            do {
                let text = try await GeminiVisionService.verify(imageData: imageData)
                await MainActor.run {
                    recognizedText = ""
                    explanation = AIReviewResult(state: .reviewed, reviewText: text)
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    explanation = AIReviewResult(
                        state: .failed(reason: error.localizedDescription),
                        reviewText: nil
                    )
                    isAnalyzing = false
                }
            }
        }
    }

    private func continueAI(with text: String) async {
        recognizedText = text
        async let aiResult = aiVerbose ? reviewService.explain(problem: text) : reviewService.review(equation: text)
        let unitRes = UnitChecker.check(text)
        let ai = await aiResult
        explanation = ai
        unitResult  = unitRes
        isAnalyzing = false
    }

    private func resetPanelState() {
        recognizedText = ""
        unitResult = nil; numericResult = nil; algebraicResult = nil
        stepReview = nil; explanation = nil; chemistryResult = nil
    }

    private func rerunAnalysis() {
        let text = recognizedText
        isAnalyzing = true; unitResult = nil
        switch panelMode {
        case .check:
            algebraicResult = nil; numericResult = nil
            Task { await continueCheck(with: text) }
        case .chemistry:
            chemistryResult = nil
            Task { await continueChemistry(with: text) }
        case .explain:
            explanation = nil
            Task { await continueAI(with: text) }
        }
    }

    // MARK: - Photo import

    private func importPhotos(_ items: [PhotosPickerItem], canvasSize: CGSize) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ui   = UIImage(data: data) else { continue }

            // Fit the photo so its longest side is ~280 pt on the canvas
            let maxSide: CGFloat = 280
            let ratio = min(maxSide / ui.size.width, maxSide / ui.size.height)
            let w = ui.size.width  * ratio
            let h = ui.size.height * ratio

            // Place at center of visible canvas area with slight random offset
            let cx = canvasSize.width  / 2 + CGFloat.random(in: -40...40)
            let cy = canvasSize.height / 2 + CGFloat.random(in: -40...40)

            let photo = CanvasPhoto(imageData: data, x: cx, y: cy, width: w, height: h)
            if let page = notepad.orderedPages.first {
                photo.page = page
                modelContext.insert(photo)
            }
        }
        pendingPhotoItems = []
    }
}

// MARK: - Comparable CGFloat clamping helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Photo card view

private struct PhotoCardView: View {
    @Bindable var photo: CanvasPhoto
    let isSelected: Bool
    let onSelect:  () -> Void
    let onDelete:  () -> Void

    @GestureState private var dragDelta:  CGSize  = .zero
    @GestureState private var scaleExtra: CGFloat = 1.0
    @GestureState private var rotExtra:   Angle   = .zero

    private var displayImage: Image? {
        UIImage(data: photo.imageData).map { Image(uiImage: $0) }
    }

    var body: some View {
        ZStack {
            (displayImage ?? Image(systemName: "photo"))
                .resizable()
                .scaledToFill()
                .frame(width:  photo.width  * scaleExtra,
                       height: photo.height * scaleExtra)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .rotationEffect(.degrees(photo.rotationDegrees) + rotExtra)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.blue, lineWidth: 2.5)
                    }
                }

            // Delete button (shown when selected)
            if isSelected {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 12, y: -12)
            }
        }
        .position(x: photo.x + dragDelta.width,
                  y: photo.y + dragDelta.height)
        .onTapGesture { onSelect() }
        .gesture(
            DragGesture()
                .updating($dragDelta) { v, state, _ in state = v.translation }
                .onEnded { v in
                    photo.x += v.translation.width
                    photo.y += v.translation.height
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .updating($scaleExtra) { v, state, _ in state = v }
                .onEnded { v in
                    photo.width  = max(60, photo.width  * v)
                    photo.height = max(60, photo.height * v)
                }
        )
        .simultaneousGesture(
            RotationGesture()
                .updating($rotExtra) { v, state, _ in state = v }
                .onEnded { v in
                    photo.rotationDegrees += v.degrees
                }
        )
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Photo", systemImage: "trash")
            }
        }
    }
}

// MARK: - Long Press Context Menu

private struct QuickActionMenu: View {
    let onGraph: () -> Void
    let onChemistry: () -> Void
    let onAI: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            pillItem(icon: "chart.line.uptrend.xyaxis", label: "Graph",   action: onGraph)
            divider
            pillItem(icon: "atom",                       label: "Chem",    action: onChemistry)
            divider
            pillItem(icon: "sparkles",                   label: "AI Help", action: onAI)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 18, y: 5)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 0.5, height: 34)
    }

    private func pillItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.blue)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ruler Bar

private struct RulerBar: View {
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.blue.opacity(0.55))
                .frame(height: 1.5)
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 30, height: 22)
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .padding(.leading, 12)
                Spacer()
            }
            GeometryReader { _ in
                Canvas { ctx, size in
                    var x: CGFloat = 0
                    while x <= size.width {
                        let isMajor = Int(x / 40) * 40 == Int(x)
                        let tickH: CGFloat = isMajor ? 8 : 4
                        let midY = size.height / 2
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: midY - tickH / 2))
                        path.addLine(to: CGPoint(x: x, y: midY + tickH / 2))
                        ctx.stroke(path, with: .color(.blue.opacity(0.35)), lineWidth: 0.75)
                        x += 20
                    }
                }
            }
            .frame(height: 28)
            .allowsHitTesting(false)
        }
        .frame(height: 28)
    }
}
#endif
