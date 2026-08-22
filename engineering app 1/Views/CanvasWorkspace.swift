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
//    • Graph and AI side-panel overlays
//    • Apple Pencil squeeze-to-erase
//
//  activeTool / penColor / rulerActive come in as bindings from the parent.
//  iOS/iPadOS only.
//

#if os(iOS)
import SwiftUI
import SwiftData

// MARK: - Pending action enum

private enum CanvasAction { case graph, check, chemistry, ai }

// MARK: - CanvasWorkspace

struct CanvasWorkspace: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var notepad: Notepad

    @Binding var activeTool: DrawingTool
    @Binding var penColor: Color
    @Binding var rulerActive: Bool

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

    // Graph
    @State private var showGraph = false
    @State private var graphEquationText: String = ""
    @State private var graphExpression: String = ""

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

                // ── Graph overlay ─────────────────────────────────────────
                if showGraph {
                    EquationGraphView(
                        equationText: graphEquationText,
                        expression: graphExpression,
                        isPresented: $showGraph
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: menuPos != nil)
            .animation(.spring(response: 0.3,  dampingFraction: 0.8),  value: holdPos != nil)
            .animation(.easeInOut(duration: 0.3), value: showGraph)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: disambiguationQueue.isEmpty)
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
                onClose: { showPanel = false; isAnalyzing = false }
            )
        }
        .onAppear(perform: ensurePage)
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

    /// Applies all stored corrections to `text` and increments their use counts.
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

        // Apply correction to working text
        disambiguationWorkingText = disambiguationWorkingText
            .replacingOccurrences(of: current.ocrFragment, with: correctionText)

        // Save to memory only when the user actually picked a different value
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
        Task {
            let rawOCR   = await EquationOCR.recognize(in: image)
            let corrected = applyStoredCorrections(rawOCR)
            let ambiguities = await reviewService.findAmbiguities(in: corrected)
            if !ambiguities.isEmpty {
                disambiguationWorkingText = corrected
                disambiguationQueue = ambiguities
                disambiguationIndex = 0
                pendingCanvasAction = .graph
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
        panelMode = .explain
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
                pendingCanvasAction = .ai
            } else {
                await continueAI(with: corrected)
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
