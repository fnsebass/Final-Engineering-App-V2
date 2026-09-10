//
//  CardChrome.swift
//  Tolerance
//
//  Shared card chrome for note/book grid cards: an adaptive (light/dark
//  aware) neutral surface with a colored border and a thicker colored
//  left-edge accent bar, rather than a solid bright fill — the accent color
//  carries the card's "subject" identity instead of the whole background.
//

import SwiftUI

private struct CardChrome: ViewModifier {
    let accent: Color
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(Color(uiColor: .secondarySystemBackground))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 4)
                    .padding(.vertical, 6)
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(accent.opacity(0.5), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    /// Wraps this view (typically a card's full VStack content, already
    /// padded) in the shared outlined-card look.
    func cardChrome(accent: Color, cornerRadius: CGFloat = 14) -> some View {
        modifier(CardChrome(accent: accent, cornerRadius: cornerRadius))
    }
}
