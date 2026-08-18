//
//  ProblemActionMenu.swift
//  Tolerance
//
//  The pill-shaped bubble shown when you long-press a problem on the canvas.
//  Its primary action, "AI this problem", opens the side panel that explains
//  how to solve the whole thing.
//

#if os(iOS)
import SwiftUI

struct ProblemActionMenu: View {
    let onAIThisProblem: () -> Void
    let onCheckUnits: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onAIThisProblem) {
                Label("AI this problem", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button(action: onCheckUnits) {
                Label("Units", systemImage: "ruler")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary))
        .shadow(radius: 8, y: 3)
    }
}
#endif
