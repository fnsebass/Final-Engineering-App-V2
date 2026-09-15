//
//  EquationKeypad.swift
//  Tolerance
//
//  A calculator-style key grid for equation-entry text fields (the graph
//  expression field and the sidebar's Quick Graph field), so writing an
//  equation doesn't require popping up the system keyboard.
//

import SwiftUI

struct EquationKeypad: View {
    var onKey: (String) -> Void

    private static let rows: [[String]] = [
        ["7", "8", "9", "(", ")"],
        ["4", "5", "6", "x", "y", "z"],
        ["1", "2", "3", "^", "."],
        ["0", "+", "−", "×", "÷"],
    ]

    private static let operators: Set<String> = ["+", "−", "×", "÷", "^"]

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.04))
    }

    private func keyButton(_ label: String) -> some View {
        let isOp = Self.operators.contains(label)
        return Button {
            switch label {
            case "×": onKey("*")
            case "÷": onKey("/")
            case "−": onKey("-")
            default:  onKey(label)
            }
        } label: {
            Text(label)
                .font(.system(size: 15, weight: isOp ? .semibold : .regular, design: .monospaced))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(isOp ? Color.orange.opacity(0.15) : Color.primary.opacity(0.05))
                .foregroundStyle(isOp ? Color.orange : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
