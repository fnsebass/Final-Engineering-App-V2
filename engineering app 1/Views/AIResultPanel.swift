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

enum PanelMode { case check, explain, chemistry }

struct AIResultPanel: View {
    @Binding var recognizedText: String
    let mode: PanelMode
    let unitResult: UnitCheckResult?
    let numericResult: NumericCheckResult?
    let algebraicResult: AlgebraicCheckResult?
    let stepReview: StepReviewResult?
    let explanation: AIReviewResult?
    let chemistryResult: ChemistryResult?
    let isAnalyzing: Bool
    let onRerun: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    recognizedSection
                    if mode != .chemistry { unitSection }
                    aiSection
                }
                .padding()
            }
            .overlay(alignment: .bottomTrailing) {
                Button(action: onClose) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
                .shadow(radius: 6, y: 2)
                .padding([.trailing, .bottom], 16)
            }
            .navigationTitle(mode == .explain ? "How to Solve" : mode == .chemistry ? "Chemistry" : "Calculation Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
        }
    }

    // MARK: - Recognized Equation

    private var recognizedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Selected Problem", systemImage: "character.cursor.ibeam")
            Text("Read from your handwriting — edit if incorrect, then re-run.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            TextField("Recognized text", text: $recognizedText, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())

            HStack {
                Spacer()
                Button(action: onRerun) {
                    Label("Re-run Analysis", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isAnalyzing || recognizedText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Unit Check

    private var unitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Unit Check", systemImage: "ruler")
                Spacer()
                Text("Deterministic")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }

            if isAnalyzing && unitResult == nil {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 4)
            } else if let result = unitResult {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: unitIcon(result.status))
                        .font(.title3)
                        .foregroundStyle(unitColor(result.status))
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.headline)
                            .font(.subheadline.weight(.semibold))
                        
                        ForEach(result.details, id: \.self) { detail in
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            } else {
                Text("No units detected to analyze.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Numeric consistency badge — only shown when the equation is purely numeric.
            if let num = numericResult {
                switch num.status {
                case .consistent:
                    numericBadge(num.headline, icon: "equal.square.fill", color: .green)
                case .inconsistent:
                    numericBadge(num.headline, icon: "exclamationmark.square.fill", color: .red)
                case .hasVariables, .noEquation, .unevaluable:
                    EmptyView()
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func numericBadge(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.top, 6)
    }

    // MARK: - AI Section

    @ViewBuilder
    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: mode == .explain   ? "AI Walkthrough"
                     : mode == .chemistry ? "Chemistry Analysis"
                     : "Algebraic Error Check",
                systemImage: mode == .chemistry ? "atom"
                           : mode == .check     ? "checkmark.seal"
                           : "sparkles"
            )

            Text(AIReviewResult.disclaimer)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if mode == .check {
                algebraicContent
            } else if mode == .chemistry {
                chemistryContent
            } else {
                explanationContent
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var stepReviewContent: some View {
        if isAnalyzing && stepReview == nil {
            thinkingRow
        } else if let review = stepReview {
            switch review.state {
            case .reviewed:
                if let verdict = review.verdict, !verdict.isEmpty {
                    Text(verdict)
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 2)
                }
                
                Label("Green = valid step · Red = calculation mistake", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(review.steps) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.text)
                                .font(.body.monospaced())
                                .underline(true, pattern: .dot, color: step.isCorrect ? .green : .red)
                            
                            if !step.isCorrect && !step.note.isEmpty {
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                    Text(step.note)
                                        .font(.caption)
                                }
                                .foregroundStyle(.red)
                            }
                        }
                    }
                }

                if review.steps.isEmpty {
                    Text("No individual solving steps detected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .modelUnavailable(let reason):
                unavailableRow(reason, system: "exclamationmark.icloud")
            case .skipped(let reason):
                unavailableRow(reason, system: "questionmark.circle")
            case .failed(let reason):
                unavailableRow("AI review failed: \(reason)", system: "xmark.octagon")
            }
        } else {
            Text("No evaluation available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var explanationContent: some View {
        if isAnalyzing && explanation == nil {
            thinkingRow
        } else if let result = explanation {
            switch result.state {
            case .reviewed:
                Text(result.reviewText ?? "No walkthrough generated.")
                    .font(.subheadline)
                    .textSelection(.enabled)
            case .modelUnavailable(let reason):
                unavailableRow(reason, system: "exclamationmark.icloud")
            case .skipped(let reason):
                unavailableRow(reason, system: "questionmark.circle")
            case .failed(let reason):
                unavailableRow("AI failed: \(reason)", system: "xmark.octagon")
            }
        } else {
            Text("No explanation available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var algebraicContent: some View {
        if isAnalyzing && algebraicResult == nil {
            thinkingRow
        } else if let res = algebraicResult {
            switch res.state {
            case .correct:
                Label(res.verdict ?? "No algebraic errors found", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.vertical, 2)

            case .hasErrors:
                if let verdict = res.verdict, !verdict.isEmpty {
                    Text(verdict)
                        .font(.subheadline.weight(.semibold))
                        .padding(.bottom, 2)
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(res.errors) { err in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                Text(err.expression)
                                    .font(.caption.monospaced())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.red.opacity(0.1),
                                                in: RoundedRectangle(cornerRadius: 5))
                                Spacer()
                                Text(err.errorType)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                            Text(err.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.green)
                                Text(err.correction)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.green)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(10)
                        .background(
                            Color(uiColor: .tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                    }
                }

            case .modelUnavailable(let reason):
                unavailableRow(reason, system: "exclamationmark.icloud")
            case .skipped(let reason):
                unavailableRow(reason, system: "questionmark.circle")
            case .failed(let reason):
                unavailableRow("Check failed: \(reason)", system: "xmark.octagon")
            }
        } else {
            Text("No algebraic check available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var chemistryContent: some View {
        if isAnalyzing && chemistryResult == nil {
            thinkingRow
        } else if let res = chemistryResult {
            switch res.state {
            case .reviewed:
                if let type = res.analysisType, !type.isEmpty {
                    Text(type)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let equation = res.result, !equation.isEmpty {
                    Text(equation)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            Color(uiColor: .tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                }
                if !res.findings.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(res.findings, id: \.self) { finding in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 6)
                                Text(finding)
                                    .font(.subheadline)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            case .modelUnavailable(let reason):
                unavailableRow(reason, system: "exclamationmark.icloud")
            case .skipped(let reason):
                unavailableRow(reason, system: "questionmark.circle")
            case .failed(let reason):
                unavailableRow("Analysis failed: \(reason)", system: "xmark.octagon")
            }
        } else {
            Text("No chemistry analysis available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Analyzing on-device…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func unavailableRow(_ text: String, system: String) -> some View {
        Label(text, systemImage: system)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Styling Helpers

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

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }
}
#endif // os(iOS)
