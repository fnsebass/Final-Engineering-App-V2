//
//  AIResultPanel.swift
//  Tolerance
//
//  The side panel. It always shows the recognized equation (editable) and the
//  deterministic Unit Check. The AI section depends on the mode:
//    • .check   – per-step review: each step is underlined with a dotted line,
//                 green if correct, red at the mistake.
//    • .explain – a step-by-step walkthrough of how to solve the problem.
//
//  iOS/iPadOS only (uses PanelMode from the workspace).
//

#if os(iOS)
import SwiftUI

struct AIResultPanel: View {
    @Binding var recognizedText: String
    let mode: PanelMode
    let unitResult: UnitCheckResult?
    let stepReview: StepReviewResult?
    let explanation: AIReviewResult?
    let isAnalyzing: Bool
    let onRerun: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                recognizedSection
                Divider()
                unitSection
                Divider()
                aiSection
            }
            .padding()
        }
        .navigationTitle(mode == .explain ? "How to Solve" : "AI Assistant")
    }

    // MARK: Recognized equation

    private var recognizedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Selected Problem", systemImage: "character.cursor.ibeam")
            Text("Read from your handwriting — edit if it's wrong, then re-run.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Recognized text", text: $recognizedText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            Button(action: onRerun) {
                Label("Re-run", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isAnalyzing || recognizedText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: Unit check

    private var unitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Unit Check", systemImage: "ruler")
            Text("Deterministic dimensional analysis — no AI.")
                .font(.caption2).foregroundStyle(.tertiary)

            if isAnalyzing && unitResult == nil {
                ProgressView().controlSize(.small)
            } else if let result = unitResult {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: unitIcon(result.status)).foregroundStyle(unitColor(result.status))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.headline).font(.subheadline.weight(.medium))
                        ForEach(result.details, id: \.self) { detail in
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("No result.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: AI section

    @ViewBuilder
    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: mode == .explain ? "AI Walkthrough" : "AI Review",
                          systemImage: "sparkles")
            Text(AIReviewResult.disclaimer)
                .font(.caption2).foregroundStyle(.tertiary)

            if mode == .check {
                stepReviewContent
            } else {
                explanationContent
            }
        }
    }

    @ViewBuilder
    private var stepReviewContent: some View {
        if isAnalyzing && stepReview == nil {
            thinkingRow
        } else if let review = stepReview {
            switch review.state {
            case .reviewed:
                if let verdict = review.verdict, !verdict.isEmpty {
                    Text(verdict).font(.subheadline.weight(.semibold))
                }
                Label("Green = correct step · Red = mistake", systemImage: "underline")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(review.steps) { step in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.text)
                            .font(.body.monospaced())
                            .underline(true, pattern: .dot, color: step.isCorrect ? .green : .red)
                        if !step.isCorrect && !step.note.isEmpty {
                            Text(step.note).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                if review.steps.isEmpty {
                    Text("The model didn't return any steps.").font(.caption).foregroundStyle(.secondary)
                }
            case .modelUnavailable(let reason):
                unavailableRow(reason, system: "exclamationmark.icloud")
            case .skipped(let reason):
                unavailableRow(reason, system: "questionmark.circle")
            case .failed(let reason):
                unavailableRow("AI review failed: \(reason)", system: "xmark.octagon")
            }
        } else {
            Text("No result.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var explanationContent: some View {
        if isAnalyzing && explanation == nil {
            thinkingRow
        } else if let result = explanation {
            switch result.state {
            case .reviewed:
                Text(result.reviewText ?? "").font(.subheadline).textSelection(.enabled)
            case .modelUnavailable(let reason):
                unavailableRow(reason, system: "exclamationmark.icloud")
            case .skipped(let reason):
                unavailableRow(reason, system: "questionmark.circle")
            case .failed(let reason):
                unavailableRow("AI failed: \(reason)", system: "xmark.octagon")
            }
        } else {
            Text("No result.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Thinking on-device…").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func unavailableRow(_ text: String, system: String) -> some View {
        Label(text, systemImage: system).font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Styling

    private func unitIcon(_ status: UnitCheckResult.Status) -> String {
        switch status {
        case .consistent: return "checkmark.seal.fill"
        case .mismatch, .additionError: return "exclamationmark.triangle.fill"
        case .oneSided: return "info.circle.fill"
        case .notApplicable, .unparseable: return "minus.circle"
        }
    }

    private func unitColor(_ status: UnitCheckResult.Status) -> Color {
        switch status {
        case .consistent: return .green
        case .mismatch, .additionError: return .orange
        case .oneSided: return .blue
        case .notApplicable, .unparseable: return .secondary
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let systemImage: String
    var body: some View { Label(title, systemImage: systemImage).font(.headline) }
}
#endif
