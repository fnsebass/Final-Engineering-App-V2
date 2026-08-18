//
//  AskAIPopup.swift
//  Tolerance
//
//  Phase 5: the small floating popup shown near the pencil tip after a circle
//  gesture is recognized. Offers a single primary action, "Ask AI".
//

#if os(iOS)
import SwiftUI

struct AskAIPopup: View {
    let onAskAI: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onAskAI) {
                Label("Ask AI", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
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
