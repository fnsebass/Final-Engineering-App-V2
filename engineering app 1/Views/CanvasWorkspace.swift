//
//  CanvasWorkspace.swift
//  Tolerance
//
//  Hosts one notepad's infinite-scroll canvas. Manages:
//    • The canvas + paper theme
//    • Long-press context menu → graph / check / chemistry / AI
//    • Handwriting disambiguation: OCR → apply stored corrections →
//      AI ambiguity check → DisambiguationCard overlay → confirmed text →
//      original action (graph/check/chem/AI). Confirmed corrections are
//      saved as HandwritingCorrection entries and reused automatically.
//    • Ruler overlay
//    • Graph: floating card (drag header to move, top-left handle to resize)
//    • Left graph drawer (pin button docks graph; arrow tab reveals it)
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

// MARK: - Pending action enum

private enum CanvasAction { case graph, check, chemistry, ai }

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

    // Stored handwriting corrections (applied automatically before every action)
    @Query(sort: \HandwritingCorrection.useCount, order: .reverse)
    private var storedCorrections: [HandwritingCorrection]

    // Long-press overlay
    @State private var holdPos: CGPoint? = nil
    @State private var menuPos: CGPoint? = nil
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

    // Graph — left drawer / pin
    @State private var graphIsPinned = false
    @State private var graphDrawerOpen = false
    @State private var drawerTypeExpr: String = ""
    @State private var drawerFocused = false

    // Photos
    @State private var selectedPhotoID: PersistentIdentifier? = nil
    @State private var pendingPhotoItems: [PhotosPickerItem] = []

    // Pencil squeeze-to-erase state
    @State private var toolBeforeErase: DrawingTool? = nil

    // Disambiguation state
    @State private var disambiguationQueue: [AmbiguousCharacter] = []
    @State private var disambiguationIndex: Int = 0
    @State private var disambiguationWorkingText: String = ""
    @State private var pendingCanvasAction: CanvasAction? = nil

    private let reviewService: any EquationReviewService = OnDeviceEquationReviewService()

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
                        onLongPressPreview: { pos in
                            withAnimation(.easeIn(duration: 0.12)) { holdPos = pos }
                        },
                        onLongPressPreviewEnd: {
                            withAnimation(.easeOut(duration: 0.15)) { holdPos = nil }
                        },
                        onLongPress: { pos, image in
                            withAnimation { holdPos = nil }
                            menuImage = image
                            menuPos = clamped(pos, in: geo.size)
                        },
                        onPencilSqueezeBegan: handleSqueezeBegan,
                        onPencilSqueezeEnded: handleSqueezeEnded
                    )
                    .ignoresSafeArea(.container, edges: .bottom)

                    // ── Photo layer (above canvas, below other overlays) ─
                    photoLayer(for: page)
                        .zIndex(1)
                } else {
                    ProgressView("Preparing…").onAppear(perform: ensurePage)
                }

                // ── Hold preview ring ─────────────────────────────────────
                if let pos = holdPos {
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 2.5)
                        .frame(width: 46, height: 46)
                        .position(pos)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
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
                    LongPressMenu(
                        onGraph:      handleGraph,
                        onUnits:      handleUnits,
                        onChemistry:  handleChemistry,
                        onAI:         handleAI
                    )
                    .position(pos)
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

                // ── Left graph drawer ──────────────────────────────────────
                graphDrawer(geo: geo)
                    .zIndex(7)

                // ── Floating graph card ────────────────────────────────────
                if showGraph && !graphIsPinned, let center = graphCardCenter {
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
                        },
                        onPin: {
                            withAnimation(.spring(response: 0.3)) {
                                graphIsPinned  = true
                                graphDrawerOpen = true
                            }
                        }
                    )
                    .frame(width: graphCardWidth)
                    .position(center)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(8)
                }

                // ── Disambiguation overlay ────────────────────────────────
                if !disambiguationQueue.isEmpty,
                   disambiguationIndex < disambiguationQueue.count {
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()
                        .zIndex(14)

                    DisambiguationCard(
                        fullText: disambiguationWorkingText,
                        ambiguity: disambiguationQueue[disambiguationIndex],
                        currentIndex: disambiguationIndex + 1,
                        total: disambiguationQueue.count,
                        onPick: { resolveCurrent(with: $0) },
                        onSkip: { skipCurrent() }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .frame(maxWidth: 540)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .zIndex(15)
                    .transition(.move(edge: .top).combined(with: .opacity))
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
            .animation(.spring(response: 0.3,  dampingFraction: 0.8),  value: holdPos != nil)
            .animation(.easeInOut(duration: 0.28), value: showGraph)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: disambiguationQueue.isEmpty)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: graphDrawerOpen)
            .photosPicker(isPresented: $showPhotoPicker,
                          selection: $pendingPhotoItems,
                          maxSelectionCount: 5,
                          matching: .images)
            .onChange(of: pendingPhotoItems) { _, items in
                Task { await importPhotos(items, canvasSize: geo.size) }
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
                if !show && !graphIsPinned {
                    graphCardCenter = nil
                }
            }
        }
        .inspector(isPresented: $showPanel) {
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
                onClose: { showPanel = false; isAnalyzing = false; resetPanelState() }
            )
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

    // MARK: - Left graph drawer

    @ViewBuilder
    private func graphDrawer(geo: GeometryProxy) -> some View {
        let drawerW: CGFloat = 330
        ZStack(alignment: .leading) {
            // Drawer panel content
            VStack(spacing: 0) {
                // Quick-graph type-in field
                VStack(alignment: .leading, spacing: 8) {
                    Label("Quick Graph", systemImage: "function")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        TextField("e.g. x^2 + sin(x)", text: $drawerTypeExpr)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.go)
                            .onSubmit { launchDrawerGraph(in: geo) }

                        Button("Plot") { launchDrawerGraph(in: geo) }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                            .disabled(drawerTypeExpr.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(14)
                .background(Color(.systemGray6))

                Divider()

                // Pinned graph (or placeholder)
                if graphIsPinned && showGraph {
                    EquationGraphView(
                        equationText: graphEquationText,
                        expression: graphExpression,
                        forceIs3D: graphForce3D,
                        isPresented: $showGraph
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                graphIsPinned = false
                                graphCardCenter = CGPoint(
                                    x: geo.size.width / 2,
                                    y: geo.size.height - 260
                                )
                            }
                        } label: {
                            Image(systemName: "pin.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Graph", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Type an equation above, or graph from the canvas and tap the pin button.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: drawerW)
            .background(.regularMaterial)
            .offset(x: graphDrawerOpen ? 0 : -drawerW)

            // Arrow tab — always at the right edge of the (possibly hidden) drawer
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    graphDrawerOpen.toggle()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.18), radius: 4, x: 2)
                    Image(systemName: graphDrawerOpen ? "chevron.left" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 22, height: 52)
            }
            .buttonStyle(.plain)
            .offset(x: graphDrawerOpen ? drawerW : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

    // MARK: - Helpers

    private func clamped(_ pos: CGPoint, in size: CGSize) -> CGPoint {
        let w: CGFloat = 380, h: CGFloat = 72
        return CGPoint(
            x: min(max(pos.x, w / 2 + 12), size.width  - w / 2 - 12),
            y: min(max(pos.y - 50, h / 2 + 12), size.height - h / 2 - 12)
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

    // MARK: - Disambiguation resolution

    private func resolveCurrent(with correctionText: String) {
        guard disambiguationIndex < disambiguationQueue.count else { return }
        let current = disambiguationQueue[disambiguationIndex]

        disambiguationWorkingText = disambiguationWorkingText
            .replacingOccurrences(of: current.ocrFragment, with: correctionText)

        if correctionText != current.ocrFragment {
            let snippet = String(disambiguationWorkingText.prefix(40))
            let entry = HandwritingCorrection(
                ocrFragment: current.ocrFragment,
                correctedFragment: correctionText,
                exampleContext: snippet
            )
            modelContext.insert(entry)
        }

        advanceOrFinalize()
    }

    private func skipCurrent() {
        advanceOrFinalize()
    }

    private func advanceOrFinalize() {
        let next = disambiguationIndex + 1
        if next < disambiguationQueue.count {
            withAnimation(.spring(response: 0.25)) { disambiguationIndex = next }
        } else {
            finalizeAction()
        }
    }

    private func finalizeAction() {
        let text   = disambiguationWorkingText
        let action = pendingCanvasAction
        withAnimation {
            disambiguationQueue = []
            disambiguationIndex = 0
        }
        pendingCanvasAction = nil

        Task {
            switch action {
            case .graph:     await continueGraph(with: text)
            case .check:     await continueCheck(with: text)
            case .chemistry: await continueChemistry(with: text)
            case .ai:        await continueAI(with: text)
            case nil:        break
            }
        }
    }

    // MARK: - Long-press action handlers (with disambiguation gate)

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
            let ambiguities = await reviewService.findAmbiguities(in: corrected)
            if !ambiguities.isEmpty {
                disambiguationWorkingText = corrected
                disambiguationQueue       = ambiguities
                disambiguationIndex       = 0
                pendingCanvasAction       = .graph
            } else {
                await continueGraph(with: corrected)
            }
        }
    }

    private func continueGraph(with text: String) async {
        let aiExpr = await reviewService.extractGraphExpression(from: text)
        let expr   = aiExpr ?? MathEvaluator.extractExpression(from: text) ?? text
        graphEquationText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        graphExpression   = expr
        withAnimation { showGraph = true }
    }

    /// Type-in graph from the drawer panel.
    private func launchDrawerGraph(in geo: GeometryProxy) {
        let expr = drawerTypeExpr.trimmingCharacters(in: .whitespaces)
        guard !expr.isEmpty else { return }
        graphEquationText = expr
        graphExpression   = expr
        graphForce3D      = nil
        graphIsPinned     = true
        graphDrawerOpen   = true
        withAnimation { showGraph = true }
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
            recognizedText = corrected
            let ambiguities = await reviewService.findAmbiguities(in: corrected)
            if !ambiguities.isEmpty {
                disambiguationWorkingText = corrected
                disambiguationQueue = ambiguities
                disambiguationIndex = 0
                pendingCanvasAction = .chemistry
            } else {
                await continueChemistry(with: corrected)
            }
        }
    }

    private func continueChemistry(with text: String) async {
        recognizedText = text
        let result = await reviewService.analyzeChemistry(problem: text)
        chemistryResult = result
        isAnalyzing = false
    }

    private func handleUnits() {
        guard let image = menuImage else { menuPos = nil; return }
        menuPos = nil; menuImage = nil
        panelMode = .check
        showPanel = true
        isAnalyzing = true
        resetPanelState()
        Task {
            let rawOCR    = await EquationOCR.recognize(in: image)
            let corrected = applyStoredCorrections(rawOCR)
            recognizedText = corrected
            let ambiguities = await reviewService.findAmbiguities(in: corrected)
            if !ambiguities.isEmpty {
                disambiguationWorkingText = corrected
                disambiguationQueue = ambiguities
                disambiguationIndex = 0
                pendingCanvasAction = .check
            } else {
                await continueCheck(with: corrected)
            }
        }
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
        async let aiResult = reviewService.explain(problem: text)
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

private struct LongPressMenu: View {
    let onGraph: () -> Void
    let onUnits: () -> Void
    let onChemistry: () -> Void
    let onAI: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            pillItem(icon: "chart.line.uptrend.xyaxis", label: "Graph",   action: onGraph)
            divider
            pillItem(icon: "checkmark.seal",             label: "Check",   action: onUnits)
            divider
            pillItem(icon: "atom",                       label: "Chem",    action: onChemistry)
            divider
            pillItem(icon: "sparkles",                   label: "AI Help", action: onAI)
        }
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
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
                    Capsule()
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
