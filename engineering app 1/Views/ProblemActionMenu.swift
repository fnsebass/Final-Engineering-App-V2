//
//  ProblemActionMenu.swift
//  Tolerance
//
//  Pill-shaped bubble that appears on long-press over a problem on the canvas.
//

#if os(iOS)
import SwiftUI

struct ProblemActionMenu: View {
    let onAIThisProblem: () -> Void
    let onCheckUnits: () -> Void
    let onVisualize: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                triggerHaptic()
                onAIThisProblem()
            } label: {
                Label("AI This", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .controlSize(.small)

            Button {
                triggerHaptic()
                onCheckUnits()
            } label: {
                Label("Units", systemImage: "ruler")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                triggerHaptic()
                onVisualize()
            } label: {
                Label("Visualize", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
#endif
