//
//  CircuitPaletteSidebar.swift
//  Tolerance
//
//  Collapsible, categorized component palette for CircuitEditorView.
//  Replaces the old always-visible horizontal icon strip — categories and
//  the component list itself are filtered by the editor's current
//  CircuitMode, so only components valid for Digital or Analog ever show.
//

#if os(iOS)
import SwiftUI

struct CircuitPaletteSidebar: View {
    let mode: CircuitMode
    let activeType: CircuitComponentType?
    var onSelect: (CircuitComponentType) -> Void

    private struct Category: Identifiable {
        let title: String
        let types: [CircuitComponentType]
        var id: String { title }
    }

    private var categories: [Category] {
        switch mode {
        case .digital:
            return [
                Category(title: "Gates", types: [.andGate, .orGate, .notGate, .nandGate, .norGate, .xorGate, .xnorGate]),
                Category(title: "Sequential", types: [.clock, .dFlipFlop, .mux2to1]),
                Category(title: "I/O", types: [.switchComp, .led, .ground])
            ]
        case .analog:
            return [
                Category(title: "Sources", types: [.battery, .ground]),
                Category(title: "Passive", types: [.resistor, .capacitor, .inductor]),
                Category(title: "I/O", types: [.switchComp, .led]),
                Category(title: "Meters", types: [.voltmeter, .ammeter])
            ]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(categories) { category in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category.title.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 96), spacing: 8)], spacing: 8) {
                            ForEach(category.types, id: \.self) { type in
                                paletteCell(type)
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .frame(width: 210)
        .background(Color(red: 0.09, green: 0.10, blue: 0.13))
        .environment(\.colorScheme, .dark)
    }

    private func paletteCell(_ type: CircuitComponentType) -> some View {
        let active = activeType == type
        return Button {
            onSelect(type)
        } label: {
            VStack(spacing: 4) {
                CircuitSymbolView(component: previewComponent(type), isSelected: false)
                    .scaleEffect(0.42)
                    .frame(height: 34)
                Text(type.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(active ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(active ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(active ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(type.rawValue)
    }

    private func previewComponent(_ type: CircuitComponentType) -> CircuitComponent {
        CircuitComponent(type: type, x: 0, y: 0, label: "")
    }
}
#endif
