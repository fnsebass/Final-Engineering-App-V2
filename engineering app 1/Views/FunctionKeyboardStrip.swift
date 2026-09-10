//
//  FunctionKeyboardStrip.swift
//  Tolerance
//
//  A horizontally-scrolling row of math-function keys (trig, roots, log,
//  calculus). Originally built into ScientificCalculatorView; extracted so
//  EquationGraphView's expression field can use the same trig keyboard.
//

import SwiftUI

struct FunctionKeyboardStrip: View {
    let keys: [String]
    let onTap: (String) -> Void

    static let trigDefaults = [
        "sin(", "cos(", "tan(",
        "asin(", "acos(", "atan(",
        "√(", "∛(", "log(", "ln(", "abs(",
        "∫(", "d/dx("
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    Button { onTap(key) } label: {
                        Text(key)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(height: 40)
    }
}
