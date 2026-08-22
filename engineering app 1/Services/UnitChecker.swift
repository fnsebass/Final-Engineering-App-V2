//

//  UnitChecker.swift

//  Tolerance

//

//  Phase 6a: a deterministic, rules-based checker for dimensional consistency.

//  It parses an equation string, resolves the physical dimensions of each side

//  (from explicit units), and reports whether they match. No AI is involved —

//  this is the app's reliable core differentiator.

//

//  Pure Swift with no platform-specific types, so it compiles everywhere and

//  can be unit-tested directly.

//



import Foundation



// MARK: - Dimensions



/// A physical dimension expressed as exponents over the seven SI base

/// dimensions: mass, length, time, electric current, temperature, amount of

/// substance, and luminous intensity.

struct Dimensions: Equatable {

    /// Exponents in the order [M, L, T, I, Θ, N, J].

    var exponents: [Double]



    static let count = 7

    static let zero = Dimensions(exponents: Array(repeating: 0, count: count))



    var isDimensionless: Bool { exponents.allSatisfy { abs($0) < 1e-6 } }



    static func * (lhs: Dimensions, rhs: Dimensions) -> Dimensions {

        Dimensions(exponents: zip(lhs.exponents, rhs.exponents).map(+))

    }



    static func / (lhs: Dimensions, rhs: Dimensions) -> Dimensions {

        Dimensions(exponents: zip(lhs.exponents, rhs.exponents).map(-))

    }



    func raised(to power: Double) -> Dimensions {

        Dimensions(exponents: exponents.map { $0 * power })

    }



    static func == (lhs: Dimensions, rhs: Dimensions) -> Bool {

        zip(lhs.exponents, rhs.exponents).allSatisfy { abs($0 - $1) < 1e-6 }

    }



    /// Convenience builder, e.g. `Dimensions(M: 1, L: 1, T: -2)` for force.

    init(M: Double = 0, L: Double = 0, T: Double = 0, I: Double = 0,

         Θ: Double = 0, N: Double = 0, J: Double = 0) {

        exponents = [M, L, T, I, Θ, N, J]

    }



    init(exponents: [Double]) { self.exponents = exponents }

}



// MARK: - Unit table



enum UnitTable {

    /// The seven base-dimension display symbols. Mass shows as kg (the SI base).

    static let baseSymbols = ["kg", "m", "s", "A", "K", "mol", "cd"]



    /// Known unit symbols mapped to their dimensions. Prefixes are handled

    /// separately (they change magnitude, not dimension).

    static let units: [String: Dimensions] = [

        // SI base

        "m": Dimensions(L: 1),

        "g": Dimensions(M: 1),

        "s": Dimensions(T: 1),

        "A": Dimensions(I: 1),

        "K": Dimensions(Θ: 1),

        "mol": Dimensions(N: 1),

        "cd": Dimensions(J: 1),

        // Time

        "min": Dimensions(T: 1), "h": Dimensions(T: 1), "hr": Dimensions(T: 1),

        "day": Dimensions(T: 1), "yr": Dimensions(T: 1),

        // Derived

        "N": Dimensions(M: 1, L: 1, T: -2),

        "Pa": Dimensions(M: 1, L: -1, T: -2),

        "bar": Dimensions(M: 1, L: -1, T: -2),

        "J": Dimensions(M: 1, L: 2, T: -2),

        "W": Dimensions(M: 1, L: 2, T: -3),

        "Hz": Dimensions(T: -1),

        "C": Dimensions(T: 1, I: 1),

        "V": Dimensions(M: 1, L: 2, T: -3, I: -1),

        "ohm": Dimensions(M: 1, L: 2, T: -3, I: -2),

        "Ω": Dimensions(M: 1, L: 2, T: -3, I: -2),

        "S": Dimensions(M: -1, L: -2, T: 3, I: 2),

        "F": Dimensions(M: -1, L: -2, T: 4, I: 2),

        "T": Dimensions(M: 1, T: -2, I: -1),

        "Wb": Dimensions(M: 1, L: 2, T: -2, I: -1),

        "H": Dimensions(M: 1, L: 2, T: -2, I: -2),

        // Angles (dimensionless)

        "rad": Dimensions.zero, "sr": Dimensions.zero,

    ]



    /// SI prefixes. Value is unused (dimensions ignore magnitude); only the

    /// key set matters when stripping a prefix from a compound symbol.

    static let prefixes: Set<Character> = [

        "Y", "Z", "E", "P", "T", "G", "M", "k", "h", "d", "c",

        "m", "u", "μ", "n", "p", "f", "a", "z", "y",

    ]



    /// Resolve a symbol to its dimension, trying an exact match first, then a

    /// single leading SI prefix (e.g. "kg" → strip "k" → "g").

    static func dimension(for symbol: String) -> Dimensions? {

        if let dim = units[symbol] { return dim }

        guard symbol.count >= 2, let first = symbol.first, prefixes.contains(first) else {

            return nil

        }

        let remainder = String(symbol.dropFirst())

        return units[remainder]

    }

}



// MARK: - Result



struct UnitCheckResult {

    enum Status {

        case consistent          // both sides share the same dimension

        case mismatch            // sides resolve to different dimensions

        case additionError       // adding/subtracting incompatible dimensions

        case oneSided            // only one side has explicit units

        case notApplicable       // no explicit units found (skip gracefully)

        case unparseable         // couldn't make sense of the input

    }



    let status: Status

    let headline: String

    let details: [String]

    let leftUnits: String?

    let rightUnits: String?

}



// MARK: - Checker



enum UnitChecker {



    static func check(_ rawEquation: String) -> UnitCheckResult {

        let tokens = Tokenizer.tokenize(rawEquation)

        guard !tokens.isEmpty else {

            return UnitCheckResult(status: .unparseable,

                                   headline: "Couldn't read an equation to check.",

                                   details: [], leftUnits: nil, rightUnits: nil)

        }

        UnitTagger.tag(tokens)



        // Split on the first top-level '='.

        if let eqIndex = topLevelEqualsIndex(tokens) {

            let leftTokens = Array(tokens[0..<eqIndex])

            let rightTokens = Array(tokens[(eqIndex + 1)...])

            return checkEquation(left: leftTokens, right: rightTokens)

        } else {

            return checkExpression(tokens)

        }

    }



    // MARK: Equation (has '=')



    private static func checkEquation(left: [Token], right: [Token]) -> UnitCheckResult {

        var leftErrors: [String] = []

        var rightErrors: [String] = []

        let leftEval = Evaluator(left).evaluate(collectingAdditionErrorsInto: &leftErrors)

        let rightEval = Evaluator(right).evaluate(collectingAdditionErrorsInto: &rightErrors)



        let additionErrors = leftErrors + rightErrors

        if !additionErrors.isEmpty {

            return UnitCheckResult(

                status: .additionError,

                headline: "Incompatible units are being added or subtracted.",

                details: additionErrors,

                leftUnits: leftEval.map { readable($0.dimensions) },

                rightUnits: rightEval.map { readable($0.dimensions) })

        }



        guard let l = leftEval, let r = rightEval else {

            return UnitCheckResult(status: .unparseable,

                                   headline: "Couldn't fully parse both sides of the equation.",

                                   details: [], leftUnits: nil, rightUnits: nil)

        }



        let leftStr = readable(l.dimensions)

        let rightStr = readable(r.dimensions)



        switch (l.hasUnits, r.hasUnits) {

        case (false, false):

            return UnitCheckResult(

                status: .notApplicable,

                headline: "No explicit units found — nothing to dimension-check.",

                details: ["Add units to your quantities (e.g. \"9.8 m/s²\") to enable this check."],

                leftUnits: nil, rightUnits: nil)

        case (true, false), (false, true):

            let sideWith = l.hasUnits ? "left" : "right"

            return UnitCheckResult(

                status: .oneSided,

                headline: "Only the \(sideWith) side has explicit units.",

                details: ["Dimensional consistency can't be verified unless both sides carry units.",

                          "Side with units resolves to \(l.hasUnits ? leftStr : rightStr)."],

                leftUnits: l.hasUnits ? leftStr : nil,

                rightUnits: r.hasUnits ? rightStr : nil)

        case (true, true):

            if l.dimensions == r.dimensions {

                return UnitCheckResult(

                    status: .consistent,

                    headline: "Units match. Both sides resolve to \(leftStr).",

                    details: [],

                    leftUnits: leftStr, rightUnits: rightStr)

            } else {

                return UnitCheckResult(

                    status: .mismatch,

                    headline: "Units don't match: left side resolves to \(leftStr), right side resolves to \(rightStr).",

                    details: ["A dimensional mismatch usually means a term is missing, extra, or mis-copied."],

                    leftUnits: leftStr, rightUnits: rightStr)

            }

        }

    }



    // MARK: Expression (no '=')



    private static func checkExpression(_ tokens: [Token]) -> UnitCheckResult {

        var errors: [String] = []

        let eval = Evaluator(tokens).evaluate(collectingAdditionErrorsInto: &errors)

        if !errors.isEmpty {

            return UnitCheckResult(status: .additionError,

                                   headline: "Incompatible units are being added or subtracted.",

                                   details: errors, leftUnits: nil, rightUnits: nil)

        }

        guard let e = eval else {

            return UnitCheckResult(status: .unparseable,

                                   headline: "Couldn't parse the expression.",

                                   details: [], leftUnits: nil, rightUnits: nil)

        }

        if e.hasUnits {

            return UnitCheckResult(status: .oneSided,

                                   headline: "Expression resolves to \(readable(e.dimensions)).",

                                   details: ["This is an expression (no \"=\"), so there's nothing to compare against."],

                                   leftUnits: readable(e.dimensions), rightUnits: nil)

        }

        return UnitCheckResult(status: .notApplicable,

                               headline: "No explicit units found — nothing to dimension-check.",

                               details: [], leftUnits: nil, rightUnits: nil)

    }



    // MARK: Helpers



    private static func topLevelEqualsIndex(_ tokens: [Token]) -> Int? {

        var depth = 0

        for (i, t) in tokens.enumerated() {

            switch t.kind {

            case .lparen: depth += 1

            case .rparen: depth -= 1

            case .equals where depth == 0: return i

            default: break

            }

        }

        return nil

    }



    /// A human-readable unit string for a dimension, e.g. "kg·m·s⁻²" or "N".

    static func readable(_ dim: Dimensions) -> String {

        if dim.isDimensionless { return "a dimensionless quantity" }



        // Prefer a single named derived unit when the dimension matches exactly.

        let named: [(String, Dimensions)] = [

            ("N", Dimensions(M: 1, L: 1, T: -2)),

            ("Pa", Dimensions(M: 1, L: -1, T: -2)),

            ("J", Dimensions(M: 1, L: 2, T: -2)),

            ("W", Dimensions(M: 1, L: 2, T: -3)),

            ("Hz", Dimensions(T: -1)),

            ("V", Dimensions(M: 1, L: 2, T: -3, I: -1)),

            ("Ω", Dimensions(M: 1, L: 2, T: -3, I: -2)),

            ("F", Dimensions(M: -1, L: -2, T: 4, I: 2)),

            ("C", Dimensions(T: 1, I: 1)),

            ("T", Dimensions(M: 1, T: -2, I: -1)),

        ]

        for (symbol, d) in named where d == dim {

            return symbol

        }



        // Otherwise build a product of base units.

        var parts: [String] = []

        for (index, exponent) in dim.exponents.enumerated() where abs(exponent) > 1e-6 {

            parts.append(UnitTable.baseSymbols[index] + superscript(exponent))

        }

        return parts.joined(separator: "·")

    }



    /// Formats an exponent as a Unicode superscript (e.g. -2 → "⁻²"), omitting

    /// an exponent of 1. Falls back to "^x" for non-integer powers.

    private static func superscript(_ value: Double) -> String {

        if abs(value - 1) < 1e-6 { return "" }

        guard abs(value.rounded() - value) < 1e-6 else {

            return "^\(clean(value))"

        }

        let intValue = Int(value.rounded())

        let map: [Character: Character] = [

            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",

            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻",

        ]

        return String(String(intValue).compactMap { map[$0] })

    }



    private static func clean(_ value: Double) -> String {

        value == value.rounded() ? String(Int(value)) : String(value)

    }

}

// MARK: - Numeric Consistency Check

struct NumericCheckResult {
    enum Status {
        case consistent    // both sides evaluate to the same value
        case inconsistent  // values differ — arithmetic error detected
        case hasVariables  // equation contains unknown variables — skip
        case noEquation    // no '=' found
        case unevaluable   // parsing/evaluation failed
    }
    let status: Status
    let headline: String
    let lhsValue: Double?
    let rhsValue: Double?
}

extension UnitChecker {

    /// Evaluates both sides of a purely-numeric equation and checks whether
    /// they are equal. Skips gracefully when variables are present.
    static func checkNumeric(_ raw: String) -> NumericCheckResult {
        let flat = raw
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        guard let eqIdx = topLevelEqualsCharIndex(flat) else {
            return NumericCheckResult(status: .noEquation,
                headline: "No '=' found — numeric check skipped.",
                lhsValue: nil, rhsValue: nil)
        }

        let lhsStr = String(flat[..<eqIdx])
        let rhsStr = String(flat[flat.index(after: eqIdx)...])

        guard isPurelyNumeric(lhsStr), isPurelyNumeric(rhsStr) else {
            return NumericCheckResult(status: .hasVariables,
                headline: "Contains variables — numeric check not applicable.",
                lhsValue: nil, rhsValue: nil)
        }

        guard let lv = MathEvaluator.evaluate(lhsStr, x: 0),
              let rv = MathEvaluator.evaluate(rhsStr, x: 0),
              lv.isFinite, rv.isFinite else {
            return NumericCheckResult(status: .unevaluable,
                headline: "Couldn't evaluate the equation numerically.",
                lhsValue: nil, rhsValue: nil)
        }

        let tol = max(abs(lv), abs(rv), 1.0) * 1e-6
        if abs(lv - rv) <= tol {
            return NumericCheckResult(status: .consistent,
                headline: "Both sides equal \(numFmt(lv))",
                lhsValue: lv, rhsValue: rv)
        } else {
            return NumericCheckResult(status: .inconsistent,
                headline: "Left = \(numFmt(lv)),  Right = \(numFmt(rv))",
                lhsValue: lv, rhsValue: rv)
        }
    }

    private static func topLevelEqualsCharIndex(_ s: String) -> String.Index? {
        var depth = 0
        for idx in s.indices {
            switch s[idx] {
            case "(": depth += 1
            case ")": depth -= 1
            case "=" where depth == 0: return idx
            default: break
            }
        }
        return nil
    }

    /// True when `expr` contains no identifiers other than known math
    /// functions and constants (sin, cos, pi, e, …).
    private static func isPurelyNumeric(_ expr: String) -> Bool {
        let known: Set<String> = [
            "sin", "cos", "tan", "sqrt", "exp", "log", "ln",
            "abs", "asin", "acos", "atan", "sqr", "pi", "e"
        ]
        guard let re = try? NSRegularExpression(pattern: "[a-zA-Z]+") else { return true }
        let lower = expr.lowercased()
        let ns = lower as NSString
        for m in re.matches(in: lower, range: NSRange(location: 0, length: ns.length)) {
            if !known.contains(ns.substring(with: m.range)) { return false }
        }
        return true
    }

    private static func numFmt(_ v: Double) -> String { String(format: "%.4g", v) }
}

