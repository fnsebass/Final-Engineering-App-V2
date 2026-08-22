//
//  MathEvaluator.swift
//  Tolerance
//
//  Parses and evaluates simple math expressions for equation graphing.
//  Supports y = f(x), z = f(x,y), and bare expressions.
//  The evaluate(_:x:y:) overload threads a second variable (y) through the
//  recursive descent parser so 3-D surface plots work automatically.
//

import Foundation

enum MathEvaluator {

    // MARK: - Public API

    /// Extracts a plottable RHS expression from text like "y = x^2 + 1",
    /// "z = x^2 + y^2", or "f(x,y) = sin(x)*cos(y)".
    static func extractExpression(from text: String) -> String? {
        let flat = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        let patterns = [
            "(?i)z\\s*=\\s*(.+)",                            // z = f(x,y)
            "(?i)y\\s*=\\s*(.+)",                            // y = f(x)
            "(?i)f\\s*\\(\\s*x\\s*,\\s*y\\s*\\)\\s*=\\s*(.+)",  // f(x,y) = ...
            "(?i)f\\s*\\(\\s*x\\s*\\)\\s*=\\s*(.+)",        // f(x) = ...
            // OCR-resilient: any non-whitespace LHS before "=".
            // Handles Vision misreading 'z' as '2', 'Z', or other characters.
            "(?i)\\S+\\s*=\\s*(.+)",
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: flat, range: NSRange(flat.startIndex..., in: flat)),
                  let captureRange = Range(match.range(at: 1), in: flat) else { continue }
            let expr = String(flat[captureRange]).trimmingCharacters(in: .whitespaces)
            if !expr.isEmpty { return expr }
        }

        // Fallback: if the text contains x or y, treat the whole thing as an expression.
        let lower = flat.lowercased()
        if lower.contains("x") || lower.contains("y") { return flat }

        return nil
    }

    /// True when the expression contains a `y` variable — signals a 3-D z = f(x,y) plot.
    static func is3DExpression(_ expr: String) -> Bool {
        expr.lowercased().contains("y")
    }

    /// Evaluate a single-variable expression (backward-compatible).
    static func evaluate(_ expression: String, x: Double) -> Double? {
        evaluate(expression, x: x, y: 0)
    }

    /// Evaluate a one- or two-variable expression.
    static func evaluate(_ expression: String, x: Double, y: Double) -> Double? {
        var lexer = Lexer(normalize(expression).lowercased())
        var tokens = lexer.tokenize()
        var pos = 0
        let result = parseExpr(&tokens, &pos, x: x, y: y)
        guard let v = result, v.isFinite else { return nil }
        return v
    }

    // MARK: - Normalisation

    /// Pre-processes an expression string before lexing.
    /// Converts Unicode math characters that OCR may produce into ASCII equivalents
    /// so the recursive-descent parser can handle them.
    static func normalize(_ expression: String) -> String {
        var s = expression
        // Unicode superscript digits → caret notation (Vision OCR reads x² as x²)
        let superscripts: [(String, String)] = [
            ("²", "^2"), ("³", "^3"), ("¹", "^1"), ("⁴", "^4"), ("⁵", "^5"),
            ("⁶", "^6"), ("⁷", "^7"), ("⁸", "^8"), ("⁹", "^9"), ("⁰", "^0"),
        ]
        for (from, to) in superscripts { s = s.replacingOccurrences(of: from, with: to) }
        // Unicode √ → sqrt  (if followed by "(", "sqrt(" is formed naturally)
        s = s.replacingOccurrences(of: "√", with: "sqrt")
        // Unicode caret lookalikes → ASCII ^
        s = s.replacingOccurrences(of: "ˆ", with: "^")   // U+02C6
        s = s.replacingOccurrences(of: "＾", with: "^")   // U+FF3E
        // Unicode multiplication signs → *
        s = s.replacingOccurrences(of: "×", with: "*")
        s = s.replacingOccurrences(of: "·", with: "*")
        return s
    }

    // MARK: - Token

    private enum Tok: Equatable {
        case num(Double)
        case varX
        case varY
        case plus, minus, star, slash, caret
        case lparen, rparen
        case fn(String)
        case end
    }

    // MARK: - Lexer

    private struct Lexer {
        private let src: [Character]
        private var i: Int = 0

        init(_ s: String) { src = Array(s) }

        mutating func tokenize() -> [Tok] {
            var rawTokens: [Tok] = []
            while i < src.count {
                let c = src[i]
                if c.isWhitespace { i += 1; continue }
                switch c {
                case "0"..."9", ".": rawTokens.append(readNum())
                case "a"..."z":      rawTokens.append(readWord())
                case "+": rawTokens.append(.plus);   i += 1
                case "-": rawTokens.append(.minus);  i += 1
                case "*": rawTokens.append(.star);   i += 1
                case "/": rawTokens.append(.slash);  i += 1
                case "^": rawTokens.append(.caret);  i += 1
                case "(": rawTokens.append(.lparen); i += 1
                case ")": rawTokens.append(.rparen); i += 1
                default:  i += 1
                }
            }
            rawTokens.append(.end)

            // Insert implicit multiplication: 2x → 2*x, 2(x+1) → 2*(x+1), etc.
            var result: [Tok] = []
            for idx in 0..<rawTokens.count {
                let current = rawTokens[idx]
                result.append(current)
                if idx + 1 < rawTokens.count {
                    let next = rawTokens[idx + 1]
                    if shouldInsertImplicitStar(between: current, and: next) {
                        result.append(.star)
                    }
                }
            }
            return result
        }

        private mutating func readNum() -> Tok {
            var s = ""
            while i < src.count && (src[i].isNumber || src[i] == ".") { s.append(src[i]); i += 1 }
            return .num(Double(s) ?? 0)
        }

        private mutating func readWord() -> Tok {
            var s = ""
            // Read only letters so that "x2" doesn't merge into an unknown word.
            // Trailing digits are left for the next readNum call, where implicit
            // multiplication will be inserted (e.g. "x2" → x * 2, better than 0).
            while i < src.count && src[i].isLetter { s.append(src[i]); i += 1 }
            switch s {
            case "x":  return .varX
            case "y":  return .varY
            case "pi": return .num(.pi)
            case "e":  return .num(Darwin.M_E)
            case "sqr": return .fn("sqrt")   // common OCR misread / abbreviation
            case "sin", "cos", "tan", "sqrt", "abs", "log", "ln", "exp",
                 "asin", "acos", "atan":
                return .fn(s)
            default:   return .num(0)
            }
        }

        private func shouldInsertImplicitStar(between current: Tok, and next: Tok) -> Bool {
            let leftIsOperand: Bool
            switch current {
            case .num, .varX, .varY, .rparen: leftIsOperand = true
            default: leftIsOperand = false
            }
            let rightIsStart: Bool
            switch next {
            case .num, .varX, .varY, .lparen, .fn: rightIsStart = true
            default: rightIsStart = false
            }
            return leftIsOperand && rightIsStart
        }
    }

    // MARK: - Parser (recursive descent, threads x and y)

    private static func parseExpr(_ t: inout [Tok], _ i: inout Int, x: Double, y: Double) -> Double? {
        var lhs = parseTerm(&t, &i, x: x, y: y)
        while i < t.count {
            switch t[i] {
            case .plus:  i += 1; if let r = parseTerm(&t, &i, x: x, y: y) { lhs = (lhs ?? 0) + r }
            case .minus: i += 1; if let r = parseTerm(&t, &i, x: x, y: y) { lhs = (lhs ?? 0) - r }
            default: return lhs
            }
        }
        return lhs
    }

    private static func parseTerm(_ t: inout [Tok], _ i: inout Int, x: Double, y: Double) -> Double? {
        var lhs = parsePow(&t, &i, x: x, y: y)
        while i < t.count {
            switch t[i] {
            case .star:  i += 1; if let r = parsePow(&t, &i, x: x, y: y) { lhs = (lhs ?? 0) * r }
            case .slash:
                i += 1
                if let r = parsePow(&t, &i, x: x, y: y), r != 0 { lhs = (lhs ?? 0) / r }
                else { return nil }
            default: return lhs
            }
        }
        return lhs
    }

    private static func parsePow(_ t: inout [Tok], _ i: inout Int, x: Double, y: Double) -> Double? {
        guard let base = parseUnary(&t, &i, x: x, y: y) else { return nil }
        if i < t.count, case .caret = t[i] {
            i += 1
            guard let exp = parsePow(&t, &i, x: x, y: y) else { return base }
            return pow(base, exp)
        }
        return base
    }

    private static func parseUnary(_ t: inout [Tok], _ i: inout Int, x: Double, y: Double) -> Double? {
        if i < t.count, case .minus = t[i] { i += 1; return parseAtom(&t, &i, x: x, y: y).map { -$0 } }
        if i < t.count, case .plus  = t[i] { i += 1 }
        return parseAtom(&t, &i, x: x, y: y)
    }

    private static func parseAtom(_ t: inout [Tok], _ i: inout Int, x: Double, y: Double) -> Double? {
        guard i < t.count else { return nil }
        switch t[i] {
        case .num(let v):
            i += 1; return v
        case .varX:
            i += 1; return x
        case .varY:
            i += 1; return y
        case .lparen:
            i += 1
            let v = parseExpr(&t, &i, x: x, y: y)
            if i < t.count, case .rparen = t[i] { i += 1 }
            return v
        case .fn(let name):
            i += 1
            if i < t.count, case .lparen = t[i] { i += 1 }
            guard let arg = parseExpr(&t, &i, x: x, y: y) else { return nil }
            if i < t.count, case .rparen = t[i] { i += 1 }
            switch name {
            case "sin":  return sin(arg)
            case "cos":  return cos(arg)
            case "tan":  return tan(arg)
            case "sqrt": return arg >= 0 ? sqrt(arg) : nil
            case "abs":  return abs(arg)
            case "log":  return arg > 0 ? log10(arg) : nil
            case "ln":   return arg > 0 ? log(arg) : nil
            case "exp":  return exp(arg)
            case "asin": return asin(arg)
            case "acos": return acos(arg)
            case "atan": return atan(arg)
            default:     return nil
            }
        default:
            return nil
        }
    }
}
