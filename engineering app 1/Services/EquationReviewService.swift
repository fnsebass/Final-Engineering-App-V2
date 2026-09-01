//
//  EquationReviewService.swift
//  Tolerance
//
//  On-device AI over the circled/long-pressed content, using Apple's
//  Foundation Models framework. Three capabilities:
//    • review(equation:)     – short free-text review (legacy/fallback)
//    • reviewSteps(problem:)  – per-step correctness for green/red underlines
//    • explain(problem:)      – full step-by-step "how to solve it" walkthrough
//

import Foundation
import FoundationModels

// MARK: - Result Types (UI-facing, platform neutral)

struct MathError: Identifiable {
    let id = UUID()
    let expression: String  // the incorrect expression as written
    let errorType: String   // short category: Arithmetic, Sign, Exponent, etc.
    let reason: String      // specific explanation of the mistake
    let correction: String  // the correct form
}

struct AlgebraicCheckResult {
    enum State: Equatable {
        case correct
        case hasErrors
        case modelUnavailable(reason: String)
        case skipped(reason: String)
        case failed(reason: String)
    }
    let state: State
    let verdict: String?
    let errors: [MathError]
}

struct ChemistryResult {
    enum State: Equatable {
        case reviewed
        case modelUnavailable(reason: String)
        case skipped(reason: String)
        case failed(reason: String)
    }
    let state: State
    let result: String?       // balanced equation or computed answer
    let analysisType: String? // e.g. "Combustion reaction"
    let findings: [String]    // bullet-point key chemistry facts
}

struct AIReviewResult {
    enum State: Equatable {
        case reviewed
        case modelUnavailable(reason: String)
        case skipped(reason: String)
        case failed(reason: String)
    }
    let state: State
    let reviewText: String?

    static let disclaimer = "On-device AI — best for straightforward equations; may struggle with complex derivations. Always double-check."
}

/// One step of the student's work, judged correct or not.
struct ReviewedStep: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isCorrect: Bool
    let note: String
}

struct StepReviewResult {
    enum State: Equatable {
        case reviewed
        case modelUnavailable(reason: String)
        case skipped(reason: String)
        case failed(reason: String)
    }
    let state: State
    let steps: [ReviewedStep]
    let verdict: String?
}

// MARK: - Guided-Generation Schema

@Generable
struct GeneratedMathError {
    @Guide(description: "The incorrect expression or step exactly as the student wrote it.")
    var expression: String

    @Guide(description: "Short error category: Arithmetic, Sign, Distribution, Exponent, Factor, Chain Rule, Substitution, Integration, etc.")
    var errorType: String

    @Guide(description: "Specific reason why it is wrong — reference the actual numbers or symbols involved.")
    var reason: String

    @Guide(description: "The correct form of this expression or step.")
    var correction: String
}

@Generable
struct GeneratedAlgebraicCheck {
    @Guide(description: "'Correct', 'Contains errors', or 'Partially correct'.")
    var verdict: String

    @Guide(description: "Each specific mathematical error found, in order of appearance. Empty array if the work is correct.")
    var errors: [GeneratedMathError]
}

@Generable
struct GeneratedChemistryAnalysis {
    @Guide(description: """
    The main result: balanced equation with integer coefficients, oxidation states, \
    electron count, or computed value. Use standard chemistry notation. \
    Example: '2H₂ + O₂ → 2H₂O' or 'Fe: +3, O: −2'. One line where possible.
    """)
    var result: String

    @Guide(description: """
    Short label for what was analyzed. \
    Examples: 'Combustion reaction', 'Redox / electron transfer', \
    'Oxidation state analysis', 'Acid-base neutralization', \
    'Electron configuration', 'Stoichiometry calculation'.
    """)
    var analysisType: String

    @Guide(description: """
    Key chemistry facts, one per entry (up to 5). \
    Examples: 'Electrons transferred: 2 per Fe atom', \
    'Molar mass H₂O: 18 g/mol', 'Reaction is exothermic (ΔH < 0)', \
    'Net ionic: H⁺ + OH⁻ → H₂O', 'Limiting reagent: O₂'. \
    Empty array if none apply.
    """)
    var findings: [String]
}

// MARK: - Handwriting Ambiguity Types

/// One character or short fragment that the OCR may have misread.
struct AmbiguousCharacter: Identifiable {
    let id = UUID()
    /// The fragment exactly as OCR produced it (e.g. "1og", "B").
    let ocrFragment: String
    /// 2-3 most likely interpretations, ordered by probability.
    let alternatives: [String]
    /// Brief reason for the ambiguity.
    let reason: String
}

@Generable
struct GeneratedAmbiguityReport {
    @Guide(description: """
    Each ambiguous fragment found. Return an EMPTY array if the text is \
    clearly readable with no genuine character ambiguity.
    """)
    var ambiguities: [GeneratedAmbiguousFragment]
}

@Generable
struct GeneratedAmbiguousFragment {
    @Guide(description: """
    The exact characters (1–5 chars) that OCR captured and that are \
    genuinely ambiguous in handwriting. Include 1-2 surrounding letters \
    for context — e.g. '1og' not just '1', 'S1n' not just 'S'. \
    Only flag characters that could plausibly be different in cursive / \
    print handwriting.
    """)
    var ocrFragment: String

    @Guide(description: """
    2 or 3 most likely correct interpretations ordered by probability. \
    Examples: ['log','1og'], ['sin','S1n'], ['8','B'], ['v','u'].
    """)
    var alternatives: [String]

    @Guide(description: "One sentence explaining which handwriting shape caused the ambiguity.")
    var reason: String
}

/// Structured output used by the AI-powered graph expression extractor.
@Generable
struct GeneratedGraphExpression {
    @Guide(description: """
    The right-hand side of the equation as a plottable expression.
    Use ONLY: x and y as variables; +, -, *, /, ^ as operators; \
    sin(), cos(), tan(), sqrt(), exp(), log(), ln(), abs() as functions.
    Fix common OCR artifacts before returning: \
    'sqr(' → 'sqrt(', 'x2' → 'x^2', 'y2' → 'y^2', a leading '2 =' or 'Z =' likely means 'z ='.
    Examples: 'z = cos(sqrt(x^2 + y^2))' → 'cos(sqrt(x^2+y^2))'; \
    'y= x2+1' → 'x^2+1'; '2 = cos(sqr(x 2 + y 2))' → 'cos(sqrt(x^2+y^2))'.
    Return empty string if no plottable equation is found.
    """)
    var expression: String
}

@Generable
struct GeneratedStepReview {
    @Guide(description: "One short sentence verdict on whether the overall work is correct.")
    var verdict: String

    @Guide(description: "Each step of the work, in the order written, judged individually.")
    var steps: [GeneratedStep]
}

@Generable
struct GeneratedStep {
    @Guide(description: "The step, written as close as possible to what the student wrote.")
    var text: String

    @Guide(description: "True only if this step is mathematically correct.")
    var isCorrect: Bool

    @Guide(description: "A brief reason when the step is incorrect; empty string when correct.")
    var note: String
}

// MARK: - Protocol

protocol EquationReviewService {
    func availabilityReason() -> String?
    func review(equation: String) async -> AIReviewResult
    func reviewSteps(problem: String) async -> StepReviewResult
    func explain(problem: String) async -> AIReviewResult
    func checkAlgebra(problem: String) async -> AlgebraicCheckResult
    func analyzeChemistry(problem: String) async -> ChemistryResult
    /// Returns a clean plottable RHS expression extracted from raw OCR text,
    /// or nil if the model is unavailable or no expression was found.
    func extractGraphExpression(from rawOCR: String) async -> String?

    /// Returns any characters in `text` that may have been misread by OCR,
    /// with 2-3 likely alternatives per fragment. Returns [] when model is
    /// unavailable or text has no ambiguous characters.
    func findAmbiguities(in text: String) async -> [AmbiguousCharacter]
}

extension EquationReviewService {
    var isAvailable: Bool { availabilityReason() == nil }
}

// MARK: - On-Device Implementation

struct OnDeviceEquationReviewService: EquationReviewService {

    // OCR symbol correction guide embedded in every instruction string.
    // Tells the model exactly what Apple Vision substitutes for handwritten
    // math symbols so it can infer the correct expression before reasoning.
    private let reviewInstructions = """
    You are a careful math and engineering tutor reviewing handwritten notes \
    captured via Apple Pencil. The text below is OCR output and WILL contain \
    symbol substitutions — apply these corrections before interpreting anything:

    INTEGRAL ∫: OCR writes "S", "J", or the word "integral". \
    "S x dx" and "J sin(x) dx" both mean an integral. \
    Definite integrals: "S_0^pi f(x) dx" = ∫₀^π f(x) dx.

    DERIVATIVE d/dx: OCR drops fraction bars, yielding "d dx f(x)" or \
    "d over dx". Also appears as f'(x), f′, or y'. \
    Second derivative: "d2/dx2" or "d²/dx²". \
    Partial derivative ∂: may appear as plain "d" or "δ".

    INFINITY ∞: appears as "oo", "00", or "inf". \
    SUMMATION Σ: appears as "E" before an index (e.g. "E n=1 to N"). \
    LIMIT: "lim x -> a" or "lim x -> oo" — the "->" is the arrow.

    SQUARE ROOT √: the handwritten radical sign has a checkmark stroke followed \
    by an overbar covering the radicand. OCR reads this as "V", "v", "\\/", or \
    drops the bar entirely. "V(x2+y2)", "vx2+y2", "\\/x^2+y^2" all mean \
    sqrt(x^2+y^2). "V" before a parenthesised or superscript expression = sqrt().

    GREEK LETTERS: α→a/A, β→B, γ→y/v, δ→d, θ→0/O, λ→A, μ→u, σ→6/o, ω→w. \
    EXPONENTS inline: "x 2"=x², "e -x"=e⁻ˣ, "m s -2"=m·s⁻². \
    OPERATORS: "<=" = ≤, ">=" = ≥, "!=" = ≠, "->" = →.

    Infer the most plausible mathematical expression from context and solve it. \
    Reply under 100 words. Use plain text only — no markdown, no asterisks, \
    no bullet symbols, no dollar signs or backslash-bracket LaTeX notation. \
    Use Unicode math symbols directly (∫ √ × → ≤ ∞ ∂). State your interpretation if ambiguous, \
    then proceed. Flag any error with the specific mistake and correction. \
    Never refuse — always give your best mathematical answer.
    """

    private let stepInstructions = """
    You are a rigorous math grader for engineering courses. The student's work \
    was captured from handwriting via Apple OCR and contains these known \
    symbol substitutions — correct for them before grading:

    INTEGRAL ∫ → "S" or "J" before a math expression. \
    "S x^2 dx" means ∫x² dx. Bounds: "S_0^1 f(x) dx" = ∫₀¹ f(x) dx.

    DERIVATIVE d/dx → "d dx" or "d" above "dx" (fraction bar lost). \
    Also f'(x), y'. Partial ∂/∂x → "df/dx" when context has two variables.

    INFINITY ∞ → "oo" or "00". SUMMATION Σ → "E n=..." notation.

    SQUARE ROOT √: radical checkmark + overbar → OCR reads "V", "v", or "\\/". \
    "V(x2+y2)" = sqrt(x^2+y^2). Any "V" before a parenthesised or \
    superscript expression is sqrt().

    GREEK: α→a, β→B, γ→y, δ→d, θ→0/O, ω→w, λ→A, μ→u. \
    EXPONENTS: "x 2"=x², "v 2"=v², inline powers. \
    OPERATORS: "<="=≤, ">="=≥, "->"=→.

    Break the work into individual steps in order. Judge each step \
    (isCorrect = true only if mathematically valid). For wrong steps, give \
    a short specific note about the actual mistake. Give a one-sentence overall \
    verdict. Handle integrals (by parts, substitution), derivatives (chain, \
    product, quotient rule), limits, ODEs, algebra, and unit manipulation. \
    Always infer the most plausible interpretation before grading.
    """

    private let algebraCheckInstructions = """
    You are a rigorous mathematics checker. Input is OCR text of handwritten algebraic work. \
    Apply the usual OCR corrections (S/J=∫, oo=∞, x2=x², d dx=d/dx) before analyzing.

    Check the work for:
    1. Arithmetic errors — wrong computed values (e.g. 3×4 written as 11)
    2. Sign errors — dropped negatives, wrong inequality direction
    3. Algebraic manipulation — wrong distribution, incorrect factoring, cancelled terms
    4. Exponent/power errors — raised to wrong power during a step
    5. Coefficient/factor errors — missing or extra multipliers
    6. Order-of-operations mistakes
    7. Calculus errors — wrong derivative rule applied, missing integration constant, \
       incorrect limits

    For EACH error found: provide the incorrect expression as written, a short category \
    label, a specific explanation referencing actual numbers or symbols, and the correction.

    If the work is mathematically correct, set verdict to 'Correct' and return empty errors.
    Always give your best interpretation even when the OCR is ambiguous.
    """

    private let chemistryInstructions = """
    You are an expert chemistry tutor. The input is OCR text from handwritten chemistry notes. \
    Correct these common OCR artifacts before analyzing:
    • Subscripts: digits following element symbols are subscripts (H2O = H₂O, CO2 = CO₂)
    • Arrows: "->" or "-->" or "→" = reaction arrow →; "<=>" or "⇌" = equilibrium ⇌
    • Charges: "2+" or "2-" after a formula = ion charge (Ca2+ = Ca²⁺)
    • Greek: "delta" or "∆" = change in a quantity; "sigma"/"pi" = bond type
    • Degree: "oC" or "C°" = °C

    Perform whichever of these analyses applies to the input:
    1. BALANCE EQUATIONS – find smallest integer coefficients so atoms and charge balance.
    2. OXIDATION STATES – assign oxidation numbers using standard rules; show each element.
    3. ELECTRON COUNTING – valence electrons, formal charges, or electrons transferred in redox.
    4. REACTION TYPE – combustion, acid-base, precipitation, redox, synthesis, decomposition, etc.
    5. STOICHIOMETRY – molar masses, moles, or limiting reagents when quantities are given.
    6. OTHER – Lewis structures, hybridisation, bond order, solubility, thermochemistry, kinetics.

    Always confirm if an equation is already balanced. Show key steps in the findings.
    Never refuse — give your best chemical interpretation even if the input is ambiguous.
    """

    private let graphExtractInstructions = """
    You extract the right-hand side of a mathematical equation from OCR text captured \
    from handwritten notes. The OCR may contain artifacts — correct them before extracting:
    • 'z' misread as '2' or 'Z' on the left of '=' → still means z = f(x,y)
    • 'sqr(' or 'S(' → sqrt(
    • digits glued to variables ('x2', 'y2') → x^2, y^2
    • Unicode superscripts (², ³) → ^2, ^3
    • SQUARE ROOT √: handwritten radical sign (checkmark + overbar) reads as \
      'V', 'v', or '\\/' before the radicand. 'V(x2+y2)', 'vx^2+y^2', \
      '\\/x2+y2' all mean sqrt(x^2+y^2). Any 'V' or 'v' directly before a \
      parenthesised or superscript expression should be read as sqrt().

    Return ONLY the RHS expression using: x, y (variables); +, -, *, /, ^ (operators); \
    sin(), cos(), tan(), sqrt(), exp(), log(), ln(), abs() (functions). \
    If no plottable equation exists, return an empty string and nothing else.
    """

    private let explainInstructions = """
    You are a patient engineering and math tutor. The student's question was \
    captured from handwritten notes via Apple OCR. Correct these symbol \
    substitutions before explaining anything:

    INTEGRAL ∫ → "S" or "J" before an expression. "S f(x) dx" = ∫f(x)dx. \
    Definite: "S_a^b f(x) dx" = ∫ₐᵇ f(x) dx.

    DERIVATIVE d/dx → "d dx", "d over dx", or f'(x). \
    PARTIAL ∂ → plain "d" in multi-variable context. \
    INFINITY ∞ → "oo". SUMMATION Σ → "E". \
    SQUARE ROOT √ → "V", "v", or "\\/" before the radicand; \
    "V(x2+y2)" = sqrt(x^2+y^2).

    GREEK: θ→0/O, ω→w, α→a, β→B, γ→y, δ→d, λ→A, μ→u. \
    EXPONENTS inline: "x 2"=x², superscripts may vanish entirely. \
    OPERATORS: "<="=≤, "->"=→.

    Identify the problem (state your interpretation of any ambiguous OCR), \
    then explain step-by-step HOW to solve it — teach the method so the \
    student can handle similar problems. Number each step. Under 200 words. \
    Use plain text only — no markdown, no asterisks for bold or italic, \
    no bullet symbols, no dollar signs or backslash-bracket LaTeX notation. \
    Use Unicode math symbols directly (∫ √ × → ≤ ∞ ∂ ²). Cover integration techniques \
    (parts, substitution, partial fractions), derivatives \
    (chain/product/quotient/implicit), limits, differential equations, and \
    engineering calculations. \
    If truly uninterpretable, describe what you see and ask what's needed.
    """

    func availabilityReason() -> String? {
        let availability = SystemLanguageModel.default.availability
        switch availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This device doesn't support Apple Intelligence, which the on-device model requires."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in Settings to enable on-device AI."
            case .modelNotReady:
                return "The on-device model is still downloading or getting ready. Please try again shortly."
            @unknown default:
                return "The on-device model is currently unavailable."
            }
        @unknown default:
            return "The on-device model status is unknown."
        }
    }

    func review(equation: String) async -> AIReviewResult {
        guard let trimmed = prepared(equation) else {
            return AIReviewResult(state: .skipped(reason: "Nothing was recognized to review."), reviewText: nil)
        }
        if let reason = availabilityReason() {
            return AIReviewResult(state: .modelUnavailable(reason: reason), reviewText: nil)
        }
        do {
            let raw = try await Task.detached(priority: .userInitiated) {
                let session = LanguageModelSession(instructions: reviewInstructions)
                let response = try await session.respond(to: ocrPrompt("Equation", trimmed))
                return response.content
            }.value
            return AIReviewResult(state: .reviewed, reviewText: AITextSanitizer.run(raw))
        } catch {
            return AIReviewResult(state: .failed(reason: error.localizedDescription), reviewText: nil)
        }
    }

    func reviewSteps(problem: String) async -> StepReviewResult {
        guard let trimmed = prepared(problem) else {
            return StepReviewResult(state: .skipped(reason: "Nothing was recognized to review."), steps: [], verdict: nil)
        }
        if let reason = availabilityReason() {
            return StepReviewResult(state: .modelUnavailable(reason: reason), steps: [], verdict: nil)
        }
        do {
            let content = try await Task.detached(priority: .userInitiated) {
                let session = LanguageModelSession(instructions: stepInstructions)
                let response = try await session.respond(
                    to: ocrPrompt("Work to review", trimmed),
                    generating: GeneratedStepReview.self
                )
                return response.content
            }.value
            let steps = content.steps.map {
                ReviewedStep(text: $0.text, isCorrect: $0.isCorrect, note: AITextSanitizer.run($0.note))
            }
            return StepReviewResult(state: .reviewed, steps: steps, verdict: AITextSanitizer.run(content.verdict))
        } catch {
            return StepReviewResult(state: .failed(reason: error.localizedDescription), steps: [], verdict: nil)
        }
    }

    func explain(problem: String) async -> AIReviewResult {
        guard let trimmed = prepared(problem) else {
            return AIReviewResult(state: .skipped(reason: "Nothing was recognized to explain."), reviewText: nil)
        }
        if let reason = availabilityReason() {
            return AIReviewResult(state: .modelUnavailable(reason: reason), reviewText: nil)
        }
        do {
            let raw = try await Task.detached(priority: .userInitiated) {
                let session = LanguageModelSession(instructions: explainInstructions)
                let response = try await session.respond(to: ocrPrompt("Problem", trimmed))
                return response.content
            }.value
            return AIReviewResult(state: .reviewed, reviewText: AITextSanitizer.run(raw))
        } catch {
            return AIReviewResult(state: .failed(reason: error.localizedDescription), reviewText: nil)
        }
    }

    func checkAlgebra(problem: String) async -> AlgebraicCheckResult {
        guard let trimmed = prepared(problem) else {
            return AlgebraicCheckResult(state: .skipped(reason: "Nothing to check."), verdict: nil, errors: [])
        }
        if let reason = availabilityReason() {
            return AlgebraicCheckResult(state: .modelUnavailable(reason: reason), verdict: nil, errors: [])
        }
        do {
            let c = try await Task.detached(priority: .userInitiated) {
                let session = LanguageModelSession(instructions: algebraCheckInstructions)
                let response = try await session.respond(
                    to: ocrPrompt("Math work to check", trimmed),
                    generating: GeneratedAlgebraicCheck.self
                )
                return response.content
            }.value
            let errors = c.errors.map { e in
                MathError(expression: e.expression,
                          errorType: AITextSanitizer.run(e.errorType),
                          reason: AITextSanitizer.run(e.reason),
                          correction: AITextSanitizer.run(e.correction))
            }
            let verdict = AITextSanitizer.run(c.verdict)
            let state: AlgebraicCheckResult.State =
                verdict.lowercased().contains("error") || !errors.isEmpty
                ? .hasErrors : .correct
            return AlgebraicCheckResult(state: state, verdict: verdict, errors: errors)
        } catch {
            return AlgebraicCheckResult(state: .failed(reason: error.localizedDescription), verdict: nil, errors: [])
        }
    }

    func analyzeChemistry(problem: String) async -> ChemistryResult {
        guard let trimmed = prepared(problem) else {
            return ChemistryResult(state: .skipped(reason: "Nothing was recognized to analyze."),
                                   result: nil, analysisType: nil, findings: [])
        }
        if let reason = availabilityReason() {
            return ChemistryResult(state: .modelUnavailable(reason: reason),
                                   result: nil, analysisType: nil, findings: [])
        }
        do {
            let c = try await Task.detached(priority: .userInitiated) {
                let session = LanguageModelSession(instructions: chemistryInstructions)
                let response = try await session.respond(
                    to: ocrPrompt("Chemistry problem", trimmed),
                    generating: GeneratedChemistryAnalysis.self
                )
                return response.content
            }.value
            let cleanResult   = AITextSanitizer.run(c.result)
            let cleanType     = AITextSanitizer.run(c.analysisType)
            let cleanFindings = c.findings.map { AITextSanitizer.run($0) }
            return ChemistryResult(state: .reviewed,
                                   result: cleanResult.isEmpty ? nil : cleanResult,
                                   analysisType: cleanType.isEmpty ? nil : cleanType,
                                   findings: cleanFindings)
        } catch {
            return ChemistryResult(state: .failed(reason: error.localizedDescription),
                                   result: nil, analysisType: nil, findings: [])
        }
    }

    func extractGraphExpression(from rawOCR: String) async -> String? {
        guard let trimmed = prepared(rawOCR) else { return nil }
        guard availabilityReason() == nil else { return nil }
        return await Task.detached(priority: .userInitiated) {
            do {
                let session = LanguageModelSession(instructions: graphExtractInstructions)
                let response = try await session.respond(
                    to: "OCR text: \(trimmed)",
                    generating: GeneratedGraphExpression.self
                )
                let expr = response.content.expression
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return expr.isEmpty ? nil : expr
            } catch {
                return nil
            }
        }.value
    }

    func findAmbiguities(in text: String) async -> [AmbiguousCharacter] {
        guard let trimmed = prepared(text) else { return [] }
        guard availabilityReason() == nil else { return [] }

        let instructions = """
        You analyze OCR output from handwritten math and engineering equations. \
        Identify ONLY fragments where a character is genuinely ambiguous — i.e. it \
        could plausibly be a different character in someone's handwriting.

        Common handwriting ambiguities to look for:
        • '1' vs 'l' (lowercase L) vs 'I' — especially inside function names: \
          '1og' might be 'log', 's1n' might be 'sin', '1im' might be 'lim'.
        • '0' vs 'O' — inside variable names or formulas.
        • '2' vs 'z' — variable z may look like 2.
        • 'B' vs '8' — coefficients or variables.
        • 'u' vs 'v' vs '√' — when 'v' or 'V' appears directly before a \
          parenthesised or superscript expression (e.g. 'V(x2+y2)', 'vx^2+y^2') \
          it is almost certainly the square root symbol √. Flag it with \
          alternatives ['sqrt(', 'v', 'u'] so the user can confirm.
        • 'S' vs '∫' — when followed by an expression and 'dx'.
        • 'x' vs '×' — multiplication.
        • 'n' vs 'h' — sometimes confused in script.

        RULES:
        - Include 1-2 surrounding characters in ocrFragment for context.
        - Return NO MORE THAN 4 ambiguities. Prioritize the most impactful ones.
        - Do NOT flag digits inside clearly numeric expressions like '3x^2 + 1'.
        - Do NOT flag characters that are unambiguous in context.
        - If text has no genuine ambiguities, return an empty ambiguities array.
        """

        return await Task.detached(priority: .userInitiated) {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(
                    to: "OCR text from handwriting: \(trimmed)",
                    generating: GeneratedAmbiguityReport.self
                )
                return response.content.ambiguities.map { a in
                    AmbiguousCharacter(
                        ocrFragment: a.ocrFragment,
                        alternatives: a.alternatives,
                        reason: a.reason
                    )
                }
            } catch {
                return []
            }
        }.value
    }

    /// Trims and returns the input, or nil if it's empty.
    private func prepared(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Wraps OCR text with a label that reminds the model, at prompt time,
    /// that the input is handwriting-OCR output with known symbol artifacts.
    private func ocrPrompt(_ label: String, _ text: String) -> String {
        "\(label) [OCR from handwriting — S/J=∫, d dx=d/dx, oo=∞, apply symbol guide]:\n\(text)"
    }
}
