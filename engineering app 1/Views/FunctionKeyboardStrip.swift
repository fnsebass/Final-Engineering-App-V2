//
//  FunctionKeyboardStrip.swift
//  Tolerance
//
//  A horizontally-scrolling row of math-function keys, grouped into
//  switchable categories (trig, hyperbolic, exponential/log, constants).
//  Originally built into ScientificCalculatorView; extracted so
//  EquationGraphView's expression field can use the same keys.
//

import SwiftUI

enum MathFunctionCategory: String, CaseIterable, Identifiable {
    case trig, hyperbolic, expLog, constants

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trig:       return "Trig"
        case .hyperbolic: return "Hyperbolic"
        case .expLog:     return "Exp & Log"
        case .constants:  return "Constants"
        }
    }

    var keys: [String] {
        switch self {
        case .trig:       return FunctionKeyboardStrip.trigDefaults
        case .hyperbolic: return FunctionKeyboardStrip.hyperbolicDefaults
        case .expLog:     return FunctionKeyboardStrip.expLogDefaults
        case .constants:  return FunctionKeyboardStrip.constantsDefaults
        }
    }
}

struct FunctionKeyboardStrip: View {
    var onTap: (String) -> Void

    static let trigDefaults = [
        "sin(", "cos(", "tan(",
        "asin(", "acos(", "atan(",
        "√(", "∛(", "abs("
    ]

    static let hyperbolicDefaults = [
        "sinh(", "cosh(", "tanh(",
        "asinh(", "acosh(", "atanh("
    ]

    static let expLogDefaults = [
        "exp(", "log(", "log2(", "ln(", "10^", "cbrt("
    ]

    static let constantsDefaults = ["π", "e"]

    @State private var category: MathFunctionCategory = .trig

    var body: some View {
        VStack(spacing: 2) {
            categoryPicker
            keyRow
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MathFunctionCategory.allCases) { cat in
                    Button { category = cat } label: {
                        Text(cat.title)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(category == cat ? Color.blue.opacity(0.18) : Color.clear, in: Capsule())
                            .foregroundStyle(category == cat ? Color.blue : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private var keyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(category.keys, id: \.self) { key in
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
            .padding(.bottom, 6)
        }
    }
}
