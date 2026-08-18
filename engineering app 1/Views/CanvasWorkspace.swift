//
//  CanvasWorkspace.swift
//  Tolerance
//
//  Ties Phases 3–6 together for a single page: the PencilKit canvas, the
//  transient circle-gesture highlight, the "Ask AI" popup, and the sliding
//  results inspector that runs the Unit Check + AI Review.
//
//  iOS/iPadOS only (depends on the PencilKit canvas).
//

#if os(iOS)
import SwiftUI

struct CanvasWorkspace: View {
    let page: Page

    // Gesture / popup state.
    @State private var gesture: CircleGesture?

    // Analysis / panel state.
    @State private var showPanel = false
    @State private var recognizedText = ""
    @State private var unitResult: UnitCheckResult?
    @State private var aiResult: AIReviewResult?
    @State private var isAnalyzing = false

    private let reviewService: EquationReviewService = OnDeviceEquationReviewService()

    var body: some View {
        GeometryReader { geo in
            PencilCanvasView(
                page: page,
                onCircleDetected: { gesture = $0 },
                onOrdinaryStroke: { if !showPanel { gesture = nil } }
            )
            .overlay {
                if let gesture {
                    gestureOverlay(gesture, in: geo.size)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .inspector(isPresented: $showPanel) {
            AIResultPanel(
                recognizedText: $recognizedText,
                unitResult: unitResult,
                aiResult: aiResult,
                isAnalyzing: isAnalyzing,
                onRerun: { analyze(text: recognizedText) }
            )
            .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        }
    }

    // MARK: - Overlay (highlight + popup)

    @ViewBuilder
    private func gestureOverlay(_ gesture: CircleGesture, in size: CGSize) -> some View {
        // Transient highlight around what was circled.
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: gesture.highlightRectInView.width,
                   height: gesture.highlightRectInView.height)
            .position(x: gesture.highlightRectInView.midX,
                      y: gesture.highlightRectInView.midY)
            .allowsHitTesting(false)

        // Popup anchored just above the loop, clamped on-screen.
        AskAIPopup(
            onAskAI: { startAnalysis(with: gesture) },
            onDismiss: { self.gesture = nil }
        )
        .position(popupPosition(for: gesture, in: size))
    }

    private func popupPosition(for gesture: CircleGesture, in size: CGSize) -> CGPoint {
        let x = min(max(gesture.anchorInView.x, 90), max(size.width - 90, 90))
        let y = max(gesture.anchorInView.y - 34, 30)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Analysis pipeline

    private func startAnalysis(with gesture: CircleGesture) {
        let image = gesture.croppedImage
        self.gesture = nil
        showPanel = true
        isAnalyzing = true
        recognizedText = ""
        unitResult = nil
        aiResult = nil

        Task {
            let text = await EquationOCR.recognize(in: image)
            recognizedText = text
            await runChecks(on: text)
        }
    }

    /// Re-run the checks against the (possibly user-edited) recognized text.
    private func analyze(text: String) {
        isAnalyzing = true
        unitResult = nil
        aiResult = nil
        Task { await runChecks(on: text) }
    }

    private func runChecks(on text: String) async {
        // Deterministic unit check first (instant).
        unitResult = UnitChecker.check(text)
        // Then the on-device AI review (may take a moment).
        aiResult = await reviewService.review(equation: text)
        isAnalyzing = false
    }
}
#endif
