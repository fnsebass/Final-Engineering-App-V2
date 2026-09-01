import SwiftUI

// MARK: - Scientific Calculator popup

struct ScientificCalculatorView: View {
    @State private var expression: String = ""
    @State private var liveResult: String = ""
    @State private var useRadians: Bool = true
    @State private var justEvaluated: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            displayArea
            Divider()
            controlRow
            Divider()
            functionScrollBar
            Divider()
            numpadGrid
        }
        .frame(width: 270)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
    }

    // MARK: Display

    private var displayArea: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(expression.isEmpty ? "0" : expression)
                    .font(.system(size: 17, design: .monospaced))
                    .foregroundStyle(expression.isEmpty ? .tertiary : .primary)
                    .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            Text(liveResult.isEmpty ? " " : liveResult)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 62, alignment: .bottomTrailing)
    }

    // MARK: Control row

    private var controlRow: some View {
        HStack(spacing: 8) {
            Picker("", selection: $useRadians) {
                Text("RAD").tag(true)
                Text("DEG").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 98)

            Spacer()

            Button("C") {
                expression = ""
                liveResult = ""
                justEvaluated = false
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.red)

            Button {
                guard !expression.isEmpty else { return }
                expression.removeLast()
                liveResult = computeLive()
            } label: {
                Image(systemName: "delete.backward.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    // MARK: Function scroll bar

    private let funcKeys = [
        "sin(", "cos(", "tan(",
        "asin(", "acos(", "atan(",
        "√(", "∛(", "log(", "ln(", "abs(",
        "∫(", "d/dx("
    ]

    private var functionScrollBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(funcKeys, id: \.self) { key in
                    Button { tap(key) } label: {
                        Text(key)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.blue.opacity(0.12), in: Capsule())
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

    // MARK: Numpad

    private let numpadRows: [[String]] = [
        ["7", "8", "9", "÷"],
        ["4", "5", "6", "×"],
        ["1", "2", "3", "−"],
        ["0", ".", "π", "+"],
        ["(", ")", "^", "e"],
    ]

    private var numpadGrid: some View {
        VStack(spacing: 1) {
            ForEach(numpadRows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(row, id: \.self) { key in
                        numKey(key)
                    }
                }
            }
            Button { tapEquals() } label: {
                Text("=")
                    .font(.system(size: 20, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .background(Color.primary.opacity(0.04))
    }

    private func numKey(_ label: String) -> some View {
        let isOp = ["÷", "×", "−", "+", "^"].contains(label)
        let isSpecial = ["π", "e", "(", ")"].contains(label)
        return Button { tap(label) } label: {
            Text(label)
                .font(.system(
                    size: isSpecial ? 16 : 18,
                    weight: isOp ? .semibold : .regular,
                    design: isSpecial ? .serif : .default
                ))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(isOp ? Color.orange.opacity(0.15) : Color.primary.opacity(0.04))
                .foregroundStyle(isOp ? Color.orange : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Input logic

    private func tap(_ s: String) {
        if justEvaluated {
            let continuers = ["÷", "×", "−", "+", "^", ")"]
            if !continuers.contains(s) { expression = "" }
            justEvaluated = false
        }

        // Auto-insert * for implicit multiplication before functions/constants
        if let last = expression.last {
            let lastIsValue = last.isNumber || last == ")" || last == "π" || last == "e"
            let newOpens = s == "(" || s == "π" || s == "e"
                || (s.first?.isLetter == true && s.count > 1 && s != "÷" && s != "×" && s != "−")
            if lastIsValue && newOpens { expression += "*" }
        }

        switch s {
        case "÷": expression += "/"
        case "×": expression += "*"
        case "−": expression += "-"
        default:  expression += s
        }

        liveResult = computeLive()
    }

    private func tapEquals() {
        switch MathEval.compute(expression, radians: useRadians) {
        case .success(let v):
            expression = fmt(v)
            liveResult = ""
        case .failure:
            liveResult = "Error"
        }
        justEvaluated = true
    }

    private func computeLive() -> String {
        guard !expression.isEmpty else { return "" }
        // Only show live result when parentheses are balanced
        let depth = expression.reduce(0) { $0 + ($1 == "(" ? 1 : $1 == ")" ? -1 : 0) }
        guard depth == 0 else { return "" }
        switch MathEval.compute(expression, radians: useRadians) {
        case .success(let v): return "= \(fmt(v))"
        case .failure:        return ""
        }
    }

    private func fmt(_ v: Double) -> String {
        if v.isNaN      { return "Error" }
        if v.isInfinite { return v > 0 ? "∞" : "-∞" }
        let tidy = (v * 1e10).rounded() / 1e10
        if tidy == tidy.rounded() && abs(tidy) < 1e15 {
            return String(Int64(tidy))
        }
        return String(format: "%.10g", tidy)
    }
}

// MARK: - Expression evaluator

private enum MathEval {
    static func compute(_ input: String, radians: Bool) -> Result<Double, Error> {
        var p = MathParser(input: input, radians: radians)
        do {
            let v = try p.expr()
            guard p.atEnd else { throw Err.unexpected }
            return .success(v)
        } catch {
            return .failure(error)
        }
    }
}

private enum Err: Error { case unexpected, badNumber, unknownIdent }

private struct MathParser {
    let src: [Character]
    var pos: Int
    let radians: Bool

    var atEnd: Bool { pos >= src.count }
    var cur: Character? { pos < src.count ? src[pos] : nil }

    init(input: String, radians: Bool) {
        src = Array(input); pos = 0; self.radians = radians
    }

    mutating func ws() { while let c = cur, c == " " || c == "\t" { pos += 1 } }

    // expr = term (('+' | '-') term)*
    mutating func expr() throws -> Double {
        var v = try term(); ws()
        while let c = cur, c == "+" || c == "-" {
            pos += 1
            let r = try term()
            v = c == "+" ? v + r : v - r
            ws()
        }
        return v
    }

    // term = power (('*' | '/') power)*
    mutating func term() throws -> Double {
        var v = try power(); ws()
        while let c = cur, c == "*" || c == "/" {
            pos += 1
            let r = try power()
            v = c == "*" ? v * r : v / r
            ws()
        }
        return v
    }

    // power = unary ('^' power)?  right-associative
    mutating func power() throws -> Double {
        let base = try unary(); ws()
        guard cur == "^" else { return base }
        pos += 1
        return Darwin.pow(base, try power())
    }

    mutating func unary() throws -> Double {
        ws()
        if cur == "-" { pos += 1; return try -unary() }
        if cur == "+" { pos += 1; return try  unary() }
        return try primary()
    }

    mutating func primary() throws -> Double {
        ws()
        guard let c = cur else { throw Err.unexpected }

        if c == "(" {
            pos += 1
            let v = try expr(); ws()
            if cur == ")" { pos += 1 }
            return v
        }
        if c.isLetter || c == "√" || c == "∛" || c == "∫" { return try ident() }
        if c.isNumber  || c == "."                         { return try number() }
        throw Err.unexpected
    }

    mutating func ident() throws -> Double {
        var name = ""
        if let c = cur, c == "√" || c == "∛" || c == "∫" {
            name = String(c); pos += 1
        } else {
            while let c = cur, c.isLetter || c == "/" { name.append(c); pos += 1 }
        }
        ws()

        // Constants
        if name == "pi" { return Double.pi }
        if name == "e"  { return M_E }

        // Ignore symbolic notations that can't be evaluated
        if name == "∫" || name == "d/dx" { throw Err.unknownIdent }

        guard cur == "(" else { throw Err.unknownIdent }
        pos += 1
        let a = try expr(); ws()
        if cur == ")" { pos += 1 }

        let toRad: Double  = radians ? a : a * .pi / 180
        let fromRad: Double = radians ? 1 : 180 / .pi

        switch name {
        case "sin":  return Darwin.sin(toRad)
        case "cos":  return Darwin.cos(toRad)
        case "tan":  return Darwin.tan(toRad)
        case "asin": return Darwin.asin(a) * fromRad
        case "acos": return Darwin.acos(a) * fromRad
        case "atan": return Darwin.atan(a) * fromRad
        case "sqrt", "√": return Darwin.sqrt(a)
        case "cbrt", "∛": return Darwin.cbrt(a)
        case "log":  return Darwin.log10(a)
        case "ln":   return Darwin.log(a)
        case "abs":  return Darwin.fabs(a)
        case "exp":  return Darwin.exp(a)
        default:     throw Err.unknownIdent
        }
    }

    mutating func number() throws -> Double {
        var s = ""
        while let c = cur, c.isNumber || c == "." { s.append(c); pos += 1 }
        // Scientific notation: only when 'e'/'E' is followed by optional sign then digit
        if let c = cur, c == "e" || c == "E" {
            let saved = pos
            var candidate = s + String(c); pos += 1
            if let n = cur, n == "+" || n == "-" { candidate += String(n); pos += 1 }
            if let n = cur, n.isNumber {
                s = candidate
                while let c = cur, c.isNumber { s.append(c); pos += 1 }
            } else {
                pos = saved // not scientific notation — leave 'e' as the constant token
            }
        }
        guard let v = Double(s) else { throw Err.badNumber }
        return v
    }
}
