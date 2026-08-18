//
//  TopToolbar.swift
//  Tolerance
//
//  The floating tool bar shown at the top of the canvas. It slides up out of
//  the way while writing (driven from CanvasWorkspace) and returns when idle.
//

#if os(iOS)
import SwiftUI

struct TopToolbar: View {
    @Binding var isEraser: Bool
    @Binding var penColor: Color
    @Binding var penWidth: Double

    /// The auto-contrast pen color (opposite of the paper) plus a few accents.
    let palette: [Color]

    var body: some View {
        HStack(spacing: 14) {
            toolButton(system: "pencil.tip", isSelected: !isEraser) { isEraser = false }
            toolButton(system: "eraser", isSelected: isEraser) { isEraser = true }

            Divider().frame(height: 22)

            ForEach(Array(palette.enumerated()), id: \.offset) { _, color in
                swatch(color)
            }

            Divider().frame(height: 22)

            HStack(spacing: 6) {
                Image(systemName: "lineweight").foregroundStyle(.secondary)
                Slider(value: $penWidth, in: 1...20)
                    .frame(width: 120)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary))
        .shadow(radius: 8, y: 3)
    }

    private func toolButton(system: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 34, height: 30)
                .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func swatch(_ color: Color) -> some View {
        let isSelected = !isEraser && color.description == penColor.description
        return Button {
            penColor = color
            isEraser = false
        } label: {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0).padding(-3))
        }
        .buttonStyle(.plain)
    }
}
#endif
