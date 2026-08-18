//
//  EquationParsing.swift
//  Tolerance
//
//  Tokenizer, unit tagger, and dimensional evaluator used by UnitChecker.
//  Kept separate to keep each piece small and testable.
//
//  The tricky part of handwritten math is telling a *unit* ("9.8 m/s²") from a
//  *variable* that happens to share a letter with a unit ("F = m·a"). The
//  UnitTagger resolves that with a positional heuristic (see below).
//

import Foundation

// MARK: - Token

final class Token {
    enum Kind: Equatable {
        case number(Double)
        case ident(String)
        case plus, minus, times, divide, caret, lparen, rparen, equals
    }

    let kind: Kind
    /// Non-nil when this identifier is a recognized unit symbol.
    let resolvedDimension: Dimensions?
    /// Whether this identifier is being treated as a unit (set by UnitTagger).
    var isUnit = false

    init(_ kind: Kind) {
        self.kind = kind
        if case let .ident(symbol) = kind {
            resolvedDimension = UnitTable.dimension(for: symbol)
        } else {
            resolvedDimension = nil
        }
    }

    /// Multi-character unit symbols (kg, Pa, mol, min, …) are essentially never
    /// used as variable names, so we always treat them as units.
    var isUnambiguousUnit: Bool {
        if case let .ident(symbol) = kind {
            return resolvedDimension != nil && symbol.count >= 2
        }
        return false
    }

    var identifierText: String? {
        if case let .ident(symbol) = kind { return symbol }
        return nil
    }
}

// MARK: - Tokenizer

enum Tokenizer {
    static func tokenize(_ raw: String) -> [Token] {
        let normalized = normalize(raw)
        var tokens: [Token] = []
        let chars = Array(normalized)
        var i = 0

        func isIdentChar(_ c: Character) -> Bool {
            c.isLetter || c == "Ω" || c == "μ" || c == "°"
        }

        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }

            if c.isNumber || c == "." {
                var text = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    text.append(chars[i]); i += 1
                }
                if let value = Double(text) { tokens.append(Token(.number(value))) }
                continue
            }

            if isIdentChar(c) {
                var text = ""
                while i < chars.count, isIdentChar(chars[i]) {
                    text.append(chars[i]); i += 1
                }
                tokens.append(Token(.ident(text)))
                continue
            }

            switch c {
            case "+": tokens.append(Token(.plus))
            case "-": tokens.append(Token(.minus))
            case "*": tokens.append(Token(.times))
            case "/": tokens.append(Token(.divide))
            case "^": tokens.append(Token(.caret))
            case "(": tokens.append(Token(.lparen))
            case ")": tokens.append(Token(.rparen))
            case "=": tokens.append(Token(.equals))
            default: break // ignore anything unrecognized
            }
            i += 1
        }
        return tokens
    }

    /// Convert common Unicode math characters (superscripts, dot/cross
    /// multiplication, fancy minus signs) into the ASCII the tokenizer expects.
    private static func normalize(_ raw: String) -> String {
        let superscripts: [Character: Character] = [
            "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
            "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-",
        ]
        var result = ""
        var inSuperscript = false
        for ch in raw {
            if let mapped = superscripts[ch] {
                if !inSuperscript { result.append("^"); inSuperscript = true }
                result.append(mapped)
                continue
            }
            inSuperscript = false
            switch ch {
            case "·", "⋅", "∙", "×", "✕", "⨯", "∗": result.append("*")
            case "÷": result.append("/")
            case "−", "–", "—": result.append("-")
            case ",": break // drop thousands separators
            default: result.append(ch)
            }
        }
        return result
    }
}

// MARK: - Unit tagger

/// Decides which identifier tokens are units versus variables.
///
/// Rule: a recognized unit symbol is treated as a unit if either
///   • it is a multi-character symbol (kg, Pa, mol, …), or
///   • it appears in a "unit segment" — a run of factors that also contains a
///     numeric coefficient or an unambiguous unit.
/// Exponent numbers (the "2" in "s²") don't count as coefficients, so "E = mc²"
/// stays all-variables.
enum UnitTagger {
    static func tag(_ tokens: [Token]) {
        let n = tokens.count
        guard n > 0 else { return }

        // Assign each token a segment id, splitting on =, parentheses, + and
        // binary -. A minus that immediately follows ^ is an exponent sign, not
        // a splitter.
        var segmentIDs = [Int?](repeating: nil, count: n)
        var current = 0
        for i in 0..<n {
            let isSplitter: Bool
            switch tokens[i].kind {
            case .equals, .lparen, .rparen, .plus:
                isSplitter = true
            case .minus:
                isSplitter = !(i > 0 && tokens[i - 1].kind == .caret)
            default:
                isSplitter = false
            }
            if isSplitter {
                current += 1
            } else {
                segmentIDs[i] = current
            }
        }

        // A number is an exponent (not a coefficient) if it follows ^ or ^-.
        func isExponentNumber(_ i: Int) -> Bool {
            guard case .number = tokens[i].kind else { return false }
            if i > 0, tokens[i - 1].kind == .caret { return true }
            if i > 1, tokens[i - 1].kind == .minus, tokens[i - 2].kind == .caret { return true }
            return false
        }

        // Group token indices by segment.
        var segments: [Int: [Int]] = [:]
        for i in 0..<n {
            if let id = segmentIDs[i] { segments[id, default: []].append(i) }
        }

        for (_, indices) in segments {
            let hasAnchor = indices.contains { i in
                (isExponentNumber(i) == false && isNumber(tokens[i])) || tokens[i].isUnambiguousUnit
            }
            for i in indices {
                guard tokens[i].resolvedDimension != nil else { continue }
                tokens[i].isUnit = tokens[i].isUnambiguousUnit || hasAnchor
            }
        }
    }

    private static func isNumber(_ token: Token) -> Bool {
        if case .number = token.kind { return true }
        return false
    }
}

// MARK: - Evaluator

/// Recursive-descent evaluator that computes the dimension of a token stream
/// and reports illegal additions/subtractions of unlike dimensions.
final class Evaluator {
    struct Value {
        var dimensions: Dimensions
        var hasUnits: Bool
    }

    private let tokens: [Token]
    private var pos = 0

    init(_ tokens: [Token]) { self.tokens = tokens }

    func evaluate(collectingAdditionErrorsInto errors: inout [String]) -> Value? {
        pos = 0
        return parseExpression(&errors)
    }

    // expr := term (('+' | '-') term)*
    private func parseExpression(_ errors: inout [String]) -> Value? {
        guard var left = parseTerm(&errors) else { return nil }
        while let kind = currentKind, kind == .plus || kind == .minus {
            advance()
            guard let right = parseTerm(&errors) else { break }
            if left.dimensions != right.dimensions {
                let verb = kind == .plus ? "add" : "subtract"
                errors.append("Can't \(verb) \(UnitChecker.readable(left.dimensions)) and \(UnitChecker.readable(right.dimensions)).")
            }
            left = Value(dimensions: left.dimensions, hasUnits: left.hasUnits || right.hasUnits)
        }
        return left
    }

    // term := factor (('*' | '/' | implicit) factor)*
    private func parseTerm(_ errors: inout [String]) -> Value? {
        guard var left = parseFactor(&errors) else { return nil }
        while let kind = currentKind {
            if kind == .times || kind == .divide {
                advance()
                guard let right = parseFactor(&errors) else { break }
                left = combine(left, right, divide: kind == .divide)
            } else if startsFactor(kind) {
                // Implicit multiplication, e.g. "2 kg" or "kg m".
                guard let right = parseFactor(&errors) else { break }
                left = combine(left, right, divide: false)
            } else {
                break
            }
        }
        return left
    }

    // factor := base ('^' signedNumber)?
    private func parseFactor(_ errors: inout [String]) -> Value? {
        guard var base = parseBase(&errors) else { return nil }
        if currentKind == .caret {
            advance()
            if let exponent = parseSignedNumber() {
                base = Value(dimensions: base.dimensions.raised(to: exponent), hasUnits: base.hasUnits)
            }
        }
        return base
    }

    // base := number | identifier | '(' expr ')' | ('-'|'+') base
    private func parseBase(_ errors: inout [String]) -> Value? {
        guard let kind = currentKind else { return nil }
        switch kind {
        case .minus, .plus:
            advance()
            return parseBase(&errors) // sign doesn't affect dimensions
        case .number:
            advance()
            return Value(dimensions: .zero, hasUnits: false)
        case .ident:
            let token = tokens[pos]
            advance()
            if token.isUnit, let dim = token.resolvedDimension {
                return Value(dimensions: dim, hasUnits: true)
            }
            return Value(dimensions: .zero, hasUnits: false) // variable
        case .lparen:
            advance()
            let inner = parseExpression(&errors)
            if currentKind == .rparen { advance() }
            return inner
        default:
            return nil
        }
    }

    private func parseSignedNumber() -> Double? {
        var sign = 1.0
        if currentKind == .minus { advance(); sign = -1 }
        else if currentKind == .plus { advance() }
        if case let .number(value)? = currentKind {
            advance()
            return sign * value
        }
        return nil
    }

    private func combine(_ lhs: Value, _ rhs: Value, divide: Bool) -> Value {
        let dims = divide ? lhs.dimensions / rhs.dimensions : lhs.dimensions * rhs.dimensions
        return Value(dimensions: dims, hasUnits: lhs.hasUnits || rhs.hasUnits)
    }

    // MARK: Cursor helpers

    private var currentKind: Token.Kind? {
        pos < tokens.count ? tokens[pos].kind : nil
    }

    private func advance() { pos += 1 }

    private func startsFactor(_ kind: Token.Kind) -> Bool {
        switch kind {
        case .number, .ident, .lparen: return true
        default: return false
        }
    }
}
