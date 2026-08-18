//
//  CanvasWorkspace.swift
//  Tolerance
//
//  Assembles the editor for one notepad: the infinite grid canvas, the
//  auto-hiding top toolbar, the circle "Ask AI" popup, the long-press pill
//  menu, and the sliding results inspector.
//
//  iOS/iPadOS only.
//

#if os(iOS)
import SwiftUI
import SwiftData

enum PanelMode { case check, explain }

struct CanvasWorkspace: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var notepad: Notepad

    // Tool state.
    @State private var isEraser = false
    @State private var penColor: Color = .black
    @State private var penWidth: Double = 3
    @State private var toolbarVisible = true

    // Gesture selections.
    @State private var circleSelection: InkSelection?
    @State private var problemSelection: InkSelection?

    // Panel / analysis state.
    @State private var showPanel = false
    @State private var mode: PanelMode = .check
    @State private var recognizedText = ""
    @State private var unitResult: UnitCheckResult?
    @State private var stepReview: StepReviewResult?
    @State private var explanation: AIReviewResult?
    @State private var isAnalyzing = false

    private let reviewService: EquationReviewService = OnDeviceEquationReviewService()

    private var palette: [Color] {
        [PaperTheme.inkColor(forPaperHex: notepad.paperColorHex), .red, .blue, .green]
    }

    var body: some View {
        Group {
            if let page = notepad.orderedPages.first {
                canvas(for: page)
            } else {
                ContentUnavailableView("Preparing…", systemImage: "hourglass")
                    .onAppear(perform: ensurePage)
            }
        }
        .inspector(isPresented: $showPanel) {
            AIResultPanel(
                recognizedText: $recognizedText,
                mode: mode,
                unitResult: unitResult,
                stepReview: stepReview,
                explanation: explanation,
                isAnalyzing: isAnalyzing,
                onRerun: { analyze(text: recognizedText) }
            )
            .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
        }
        .onAppear {
            penColor = PaperTheme.inkColor(forPaperHex: notepad.paperColorHex)
            ensurePage()
        }
        .onChange(of: notepad.paperColorHex) { _, hex in
            // Pen always tracks the opposite of the paper.
            penColor = PaperTheme.inkColor(forPaperHex: hex)
        }
    }

    // MARK: - Canvas + overlays

    private func canvas(for page: Page) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                PencilCanvasView(
                    page: page,
                    paperColorHex: notepad.paperColorHex,
                    gridSpacing: notepad.gridSpacing,
                    showsGrid: notepad.showsGrid,
                    isEraser: $isEraser,
                    penColor: $penColor,
                    penWidth: $penWidth,
                    onCircleDetected: { circleSelection = $0; problemSelection = nil },
                    onLongPressProblem: { problemSelection = $0; circleSelection = nil },
                    onWritingChanged: { writing in
                        withAnimation(.easeInOut(duration: 0.2)) { toolbarVisible = !writing }
                    },
                    onOrdinaryStroke: {
                        if !showPanel { circleSelection = nil; problemSelection = nil }
                    }
                )
                .ignoresSafeArea(.container, edges: .bottom)

                if toolbarVisible {
                    TopToolbar(isEraser: $isEraser, penColor: $penColor, penWidth: $penWidth, palette: palette)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let selection = circleSelection {
                    highlight(selection)
                    AskAIPopup(
                        onAskAI: { startAnalysis(with: selection, mode: .check) },
                        onDismiss: { circleSelection = nil }
                    )
                    .position(popupPosition(for: selection, in: geo.size))
                }

                if let selection = problemSelection {
                    highlight(selection)
                    ProblemActionMenu(
                        onAIThisProblem: { startAnalysis(with: selection, mode: .explain) },
                        onCheckUnits: { startAnalysis(with: selection, mode: .check) },
                        onDismiss: { problemSelection = nil }
                    )
                    .position(popupPosition(for: selection, in: geo.size))
                }
            }
        }
    }

    private func highlight(_ selection: InkSelection) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: selection.highlightRectInView.width,
                   height: selection.highlightRectInView.height)
            .position(x: selection.highlightRectInView.midX,
                      y: selection.highlightRectInView.midY)
            .allowsHitTesting(false)
    }

    private func popupPosition(for selection: InkSelection, in size: CGSize) -> CGPoint {
        let x = min(max(selection.anchorInView.x, 120), max(size.width - 120, 120))
        let y = max(selection.anchorInView.y - 36, 30)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Analysis

    private func startAnalysis(with selection: InkSelection, mode: PanelMode) {
        self.mode = mode
        let image = selection.croppedImage
        circleSelection = nil
        problemSelection = nil
        showPanel = true
        isAnalyzing = true
        recognizedText = ""
        unitResult = nil
        stepReview = nil
        explanation = nil

        Task {
            let text = await EquationOCR.recognize(in: image)
            recognizedText = text
            await runChecks(on: text)
        }
    }

    private func analyze(text: String) {
        isAnalyzing = true
        unitResult = nil
        stepReview = nil
        explanation = nil
        Task { await runChecks(on: text) }
    }

    private func runChecks(on text: String) async {
        unitResult = UnitChecker.check(text)
        switch mode {
        case .check:
            stepReview = await reviewService.reviewSteps(problem: text)
        case .explain:
            explanation = await reviewService.explain(problem: text)
        }
        isAnalyzing = false
    }

    // MARK: - Helpers

    private func ensurePage() {
        guard notepad.orderedPages.isEmpty else { return }
        let page = Page(pageIndex: 0)
        page.notepad = notepad
        modelContext.insert(page)
    }
}
#endif
