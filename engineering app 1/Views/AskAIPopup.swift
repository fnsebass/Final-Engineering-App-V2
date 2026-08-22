//
//  AskAIPopup.swift
//  Tolerance
//
//  Phase 5: The floating popup shown near the pencil tip after a circle
//  gesture is recognized. Offers quick primary actions ("Check Units" / "Explain")
//  to directly open the side panel in the desired mode.
//

#if os(iOS)
import SwiftUI

struct AskAIPopup: View {
    let onAskAI: () -> Void
    let onExplain: (() -> Void)?
    let onDismiss: () -> Void

    init(
        onAskAI: @escaping () -> Void,
        onExplain: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.onAskAI = onAskAI
        self.onExplain = onExplain
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: 8) {
            // Primary Action: Ask AI / Check Steps
            Button(action: onAskAI) {
                Label("Check Steps", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            // Optional Secondary Direct Action: Walkthrough / Explain
            if let onExplain {
                Button(action: onExplain) {
                    Label("Explain", systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)

            // Dismiss Button with explicit touch target
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss action popup")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: true)
    }
}

// MARK: - Previews

#Preview("Ask AI Floating Popup") {
    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()
        
        AskAIPopup(
            onAskAI: { print("Ask AI tapped") },
            onExplain: { print("Explain tapped") },
            onDismiss: { print("Dismissed") }
        )
    }
}
#endif // os(iOS)
