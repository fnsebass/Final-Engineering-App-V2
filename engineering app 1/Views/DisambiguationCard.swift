//
//  DisambiguationCard.swift
//  Tolerance
//
//  Floating overlay card shown on the canvas when the AI finds an ambiguous
//  character in OCR output. The ambiguous fragment is underlined in orange
//  inside the full equation text so the user can see exactly what's unclear.
//

#if os(iOS)
import SwiftUI

struct DisambiguationCard: View {
    /// Full (working) equation text with the fragment still present.
    let fullText: String
    /// The specific ambiguity to resolve right now.
    let ambiguity: AmbiguousCharacter
    /// 1-based index of this ambiguity in the current session.
    let currentIndex: Int
    let total: Int
    /// Called with the chosen replacement string.
    let onPick: (String) -> Void
    let onSkip: () -> Void

    @State private var showCustom = false
    @State private var customText = ""
    @FocusState private var customFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            equationDisplay
            reasonText
            actionRow
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.orange.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.20), radius: 20, y: 6)
        .onChange(of: ambiguity.id) { _, _ in
            showCustom = false
            customText = ""
        }
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
            Text("Clarify Handwriting")
                .font(.headline)
            Spacer()
            if total > 1 {
                Text("\(currentIndex) of \(total)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// OCR text rendered with the ambiguous fragment underlined in orange.
    private var equationDisplay: some View {
        highlightedText
            .font(.system(.body, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 8)
            )
    }

    private var reasonText: some View {
        Label(ambiguity.reason, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            // Alternative buttons — max 3
            ForEach(ambiguity.alternatives.prefix(3), id: \.self) { alt in
                Button {
                    onPick(alt)
                } label: {
                    Text(alt)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            // Custom text field + submit button
            if showCustom {
                HStack(spacing: 6) {
                    TextField("Type it", text: $customText)
                        .focused($customFocused)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit { submitCustom() }
                    Button(action: submitCustom) {
                        Image(systemName: "return")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(customText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Button("Other…") {
                    showCustom = true
                    customFocused = true
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Skip") { onSkip() }
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    private func submitCustom() {
        let t = customText.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { onPick(t) }
    }

    // MARK: - Highlighted text (SwiftUI Text concatenation)

    private var highlightedText: Text {
        let fragment = ambiguity.ocrFragment
        if let range = fullText.range(of: fragment) {
            let before = String(fullText[..<range.lowerBound])
            let after  = String(fullText[range.upperBound...])
            let styled = Text(fragment)
                .underline(color: .orange)
                .foregroundStyle(Color.orange)
                .bold()
            return Text("\(Text(before))\(styled)\(Text(after))")
        }
        return Text(fullText)
    }
}
#endif
