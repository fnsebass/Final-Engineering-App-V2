//
//  AIResultPanel.swift
//  Tolerance
//
//  Phase 6: the side panel that shows BOTH v1 checks for the circled content —
//  the deterministic Unit Check and the on-device AI Review — clearly separated
//  under their own headers.
//
//  Plain SwiftUI (no platform-specific types) so it compiles everywhere.
//

import SwiftUI

struct AIResultPanel: View {
    /// The recognized equation, editable so users can correct OCR mistakes.
    @Binding var recognizedText: String
    let unitResult: UnitCheckResult?
    let aiResult: AIReviewResult?
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
        .navigationTitle("AI Assistant")
    }

    // MARK: Recognized equation

    private var recognizedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Circled Equation", systemImage: "character.cursor.ibeam")
            Text("Read from your handwriting — edit if it's wrong, then re-check.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Recognized equation", text: $recognizedText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            Button(action: onRerun) {
                Label("Re-check", systemImage: "arrow.clockwise")
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
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if isAnalyzing && unitResult == nil {
                ProgressView().controlSize(.small)
            } else if let result = unitResult {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: unitIcon(result.status))
                        .foregroundStyle(unitColor(result.status))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.headline)
                            .font(.subheadline.weight(.medium))
                        ForEach(result.details, id: \.self) { detail in
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("No result.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: AI review

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "AI Review", systemImage: "sparkles")
            Text(AIReviewResult.disclaimer)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if isAnalyzing && aiResult == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Thinking on-device…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let result = aiResult {
                switch result.state {
                case .reviewed:
                    Text(result.reviewText ?? "")
                        .font(.subheadline)
                        .textSelection(.enabled)
                case .modelUnavailable(let reason):
                    Label(reason, systemImage: "exclamationmark.icloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .skipped(let reason):
                    Label(reason, systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let reason):
                    Label("AI review failed: \(reason)", systemImage: "xmark.octagon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No result.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Styling helpers

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
