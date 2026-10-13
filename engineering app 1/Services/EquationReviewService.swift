//
//  EquationReviewService.swift
//  Tolerance
//
//  On-device AI over the circled/long-pressed content, using Apple's
//  Foundation Models framework — fully on-device, no network call.
//
//  Two families of entry points:
//    • Image-first (review/explain/checkAlgebra/analyzeChemistry/
//      extractGraphExpression taking a CGImage) — the model reads the
//      handwriting photo directly via multimodal Attachment support. This
//      is the primary path: one on-device inference instead of an OCR pass
//      followed by a second inference, and the model sees the real strokes
//      instead of Vision's text guesses.
//    • Text-based (the same names taking a String) — used only when the
//      user has manually edited the "Selected Problem" transcription in
//      AIResultPanel and taps Re-run.
//

import CoreGraphics
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

// MARK: - Image-First Guided-Generation Schemas
//
// These mirror the text-based schemas above but are used when the model
// reads the handwriting photo directly (see "Image-First Implementation"
// below), so each also returns a `transcription` — a clean typed rendering
// of what the model read, shown to the user as the editable "Selected
// Problem" field and reused verbatim if they tap Re-run without editing it.

@Generable
struct GeneratedImageReview {
    @Guide(description: "The problem exactly as handwritten, transcribed into typed math notation using Unicode symbols directly (∫ √ × ² etc). Not the solution — just what's written.")
    var transcription: String

    @Guide(description: "The review, check, or explanation itself, following the task instructions.")
    var answer: String
}

@Generable
struct GeneratedImageAlgebraicCheck {
    @Guide(description: "The work exactly as handwritten, transcribed into typed math notation using Unicode symbols directly (∫ √ × ² etc).")
    var transcription: String

    @Guide(description: "'Correct', 'Contains errors', or 'Partially correct'.")
    var verdict: String

    @Guide(description: "Each specific mathematical error found, in order of appearance. Empty array if the work is correct.")
    var errors: [GeneratedMathError]
}

@Generable
struct GeneratedImageChemistryAnalysis {
    @Guide(description: "The problem exactly as handwritten, transcribed into typed notation using Unicode symbols directly (₂ ⁺ → etc).")
    var transcription: String

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

@Generable
struct GeneratedImageGraphExpression {
    @Guide(description: "The equation exactly as handwritten, transcribed into typed math notation using Unicode symbols directly.")
    var transcription: String

    @Guide(description: """
    The right-hand side of the equation as a plottable expression. \
    Use ONLY: x and y as variables; +, -, *, /, ^ as operators; \
    sin(), cos(), tan(), sqrt(), exp(), log(), ln(), abs() as functions. \
    Example: 'z = cos(√(x²+y²))' → 'cos(sqrt(x^2+y^2))'. \
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

    // Text entry points — used when the user has manually edited the
    // "Selected Problem" transcription and taps Re-run.
    func review(equation: String) async -> AIReviewResult
    func reviewSteps(problem: String) async -> StepReviewResult
    func explain(problem: String) async -> AIReviewResult
    func checkAlgebra(problem: String) async -> AlgebraicCheckResult
    func analyzeChemistry(problem: String) async -> ChemistryResult

    // Image-first entry points — the model reads the handwriting photo
    // directly instead of going through Vision OCR first. Faster (one
    // on-device inference instead of OCR-then-inference) and more accurate
    // (the model sees the real glyphs instead of Vision's text guesses).
    // Each also returns a `transcription` to populate the editable
    // "Selected Problem" field.
    func review(image: CGImage) async -> (transcription: String, result: AIReviewResult)
    func explain(image: CGImage) async -> (transcription: String, result: AIReviewResult)
    func checkAlgebra(image: CGImage) async -> (transcription: String, result: AlgebraicCheckResult)
    func analyzeChemistry(image: CGImage) async -> (transcription: String, result: ChemistryResult)
    /// Returns nil if the model is unavailable or no plottable expression was found.
    func extractGraphExpression(from image: CGImage) async -> (transcription: String, expression: String)?
}

extension EquationReviewService {
    var isAvailable: Bool { availabilityReason() == nil }
}

// MARK: - On-Device Implementation

struct OnDeviceEquationReviewService: EquationReviewService {

    // Shared guidance on resolving individual-character misreads, embedded
    // in every instruction string below. Apple's handwriting OCR (EquationOCR)
    // has no math-specific model, so it frequently confuses visually similar
    // isolated glyphs — this is the model's chance to use surrounding math
    // context (which the glyph-level OCR doesn't have) to fix that.
    private static let ambiguousCharacterGuide = """
    AMBIGUOUS CHARACTERS: The OCR frequently confuses visually similar \
    handwritten characters, most commonly x↔z, +↔=, 1↔l↔I, 0↔O, 5↔S, 2↔z, \
    6↔b, 9↔g, and n↔h. When the OCR text contains a bracketed alternate like \
    "x[or z]", silently choose whichever reading makes the surrounding \
    equation mathematically valid, then drop the brackets — never repeat the \
    bracket notation back in your answer. Even without brackets, if the most \
    literal reading of a character would make the expression nonsensical \
    (e.g. two operators in a row, a variable that appears from nowhere, an \
    equation that can't balance), silently substitute whichever visually \
    similar character makes it valid before solving.
    """

    // OCR symbol correction guide embedded in every instruction string.
    // Tells the model exactly what Apple Vision substitutes for handwritten
    // math symbols so it can infer the correct expression before reasoning.
    private let reviewInstructionsBase = """
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

    \(Self.ambiguousCharacterGuide)

    Infer the most plausible mathematical expression from context and solve it. \
    Keep your answer concise, but always finish your last sentence completely — \
    never cut off mid-word or mid-step. Use plain text only — no markdown, no \
    asterisks, no bullet symbols, no dollar signs or backslash-bracket LaTeX \
    notation. Use Unicode math symbols directly (∫ √ × → ≤ ∞ ∂). State your \
    interpretation if ambiguous, then proceed. Flag any error with the specific \
    mistake and correction. Never refuse — always give your best mathematical answer.
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

    \(Self.ambiguousCharacterGuide)

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

    \(Self.ambiguousCharacterGuide)

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

    private let explainInstructionsBase = """
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

    \(Self.ambiguousCharacterGuide)

    Identify the problem (state your interpretation of any ambiguous OCR), \
    then explain step-by-step HOW to solve it — teach the method so the \
    student can handle similar problems. Number each step. Keep the \
    walkthrough focused, but always finish completely — never cut off \
    mid-step or mid-sentence. \
    Use plain text only — no markdown, no asterisks for bold or italic, \
    no bullet symbols, no dollar signs or backslash-bracket LaTeX notation. \
    Use Unicode math symbols directly (∫ √ × → ≤ ∞ ∂ ²). Cover integration techniques \
    (parts, substitution, partial fractions), derivatives \
    (chain/product/quotient/implicit), limits, differential equations, and \
    engineering calculations. \
    If truly uninterpretable, describe what you see and ask what's needed.
    """

    // MARK: - Tutor Interactions preferences (Settings → Intelligence → Tutor Interactions)

    /// Extra guidance appended to the review/explain instructions based on the
    /// Hint Style picker and the free-text Custom Prompting field. Read directly
    /// from UserDefaults since this struct isn't a SwiftUI view.
    nonisolated private var tutorPreferenceSuffix: String {
        var lines: [String] = []

        switch UserDefaults.standard.string(forKey: "settings.tutor.hintMode") {
        case "minimal":
            lines.append("Give only a single short hint toward the next step — do not fully solve the problem.")
        case "full":
            lines.append("Be thorough: explain the underlying concept as well as the steps.")
        default:
            break // "guided" (default) needs no extra instruction.
        }

        let custom = UserDefaults.standard.string(forKey: "settings.tutor.customPrompt")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty {
            lines.append("Additional user preference: \(custom)")
        }

        return lines.isEmpty ? "" : "\n\n" + lines.joined(separator: " ")
    }

    nonisolated private var reviewInstructions: String { reviewInstructionsBase + tutorPreferenceSuffix }
    nonisolated private var explainInstructions: String { explainInstructionsBase + tutorPreferenceSuffix }

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

    // MARK: - Image-First Implementation
    //
    // These read the handwriting photo directly via Foundation Models'
    // multimodal `Attachment` support rather than going through Vision OCR
    // first — one on-device inference instead of OCR-then-inference, and
    // the model sees the real strokes instead of Vision's text guesses.

    /// Shared guidance for interpreting handwriting conventions directly
    /// from the image — distinct from `ambiguousCharacterGuide` above, which
    /// is specifically about correcting Vision OCR's text-level mistakes.
    private static let imageHandwritingGuide = """
    This is a photo of handwritten engineering/math notes from an iPad. \
    Handwriting can be messy — apply these conventions: a checkmark with a \
    bar over the radicand is a square root (√); a fraction bar stacks the \
    numerator directly above the denominator, so "d" written above "dx" \
    means d/dx; an integral sign can look like a tall, narrow S or J; \
    infinity (∞) is a sideways figure-eight; Σ for summation may look like \
    a sideways 3 or E; Greek letters written quickly can resemble similar \
    Latin letters (θ like a 0 with a line through it, λ like a lowercase a). \
    If anything is genuinely ambiguous, infer the most mathematically \
    sensible reading from context and proceed — never refuse.
    """

    private var imageReviewInstructions: String {
        "You are a careful math and engineering tutor reviewing a photo of handwritten notes captured via Apple Pencil.\n\n"
        + Self.imageHandwritingGuide
        + "\n\nTranscribe what's written, then solve or check it. Keep your answer concise, but always finish your last sentence completely. Use plain text only — no markdown, no asterisks, no bullet symbols, no dollar signs or backslash-bracket LaTeX notation. Use Unicode math symbols directly (∫ √ × → ≤ ∞ ∂). Flag any error with the specific mistake and correction. Never refuse — always give your best mathematical answer."
        + tutorPreferenceSuffix
    }

    private var imageExplainInstructions: String {
        "You are a patient engineering and math tutor looking at a photo of a student's handwritten notes.\n\n"
        + Self.imageHandwritingGuide
        + "\n\nTranscribe the problem, then explain step-by-step HOW to solve it — teach the method so the student can handle similar problems. Number each step. Keep the walkthrough focused, but always finish completely — never cut off mid-step or mid-sentence. Use plain text only — no markdown, no asterisks for bold or italic, no bullet symbols, no dollar signs or backslash-bracket LaTeX notation. Use Unicode math symbols directly (∫ √ × → ≤ ∞ ∂ ²). Cover integration techniques (parts, substitution, partial fractions), derivatives (chain/product/quotient/implicit), limits, differential equations, and engineering calculations. If truly uninterpretable, describe what you see and ask what's needed."
        + tutorPreferenceSuffix
    }

    private let imageAlgebraCheckInstructions = """
    You are a rigorous mathematics checker looking at a photo of handwritten algebraic work.

    \(Self.imageHandwritingGuide)

    Transcribe the work, then check it for:
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
    """

    private let imageChemistryInstructions = """
    You are an expert chemistry tutor looking at a photo of handwritten chemistry notes.

    \(Self.imageHandwritingGuide)
    Chemistry-specific notation: digits following element symbols are subscripts \
    (H2O = H₂O); "2+"/"2-" after a formula is an ion charge (Ca2+ = Ca²⁺); \
    "->" or "-->" is a reaction arrow →; "<=>" is equilibrium ⇌.

    Transcribe the problem, then perform whichever analysis applies:
    1. BALANCE EQUATIONS – find smallest integer coefficients so atoms and charge balance.
    2. OXIDATION STATES – assign oxidation numbers using standard rules; show each element.
    3. ELECTRON COUNTING – valence electrons, formal charges, or electrons transferred in redox.
    4. REACTION TYPE – combustion, acid-base, precipitation, redox, synthesis, decomposition, etc.
    5. STOICHIOMETRY – molar masses, moles, or limiting reagents when quantities are given.
    6. OTHER – Lewis structures, hybridisation, bond order, solubility, thermochemistry, kinetics.

    Always confirm if an equation is already balanced. Show key steps in the findings.
    Never refuse — give your best chemical interpretation even if the input is ambiguous.
    """

    private let imageGraphExtractInstructions = """
    You extract a plottable equation from a photo of handwritten notes.

    \(Self.imageHandwritingGuide)

    Transcribe the equation, then return ONLY its right-hand side using: \
    x, y (variables); +, -, *, /, ^ (operators); \
    sin(), cos(), tan(), sqrt(), exp(), log(), ln(), abs() (functions). \
    If no plottable equation exists, return an empty string for the expression.
    """

    func review(image: CGImage) async -> (transcription: String, result: AIReviewResult) {
        if let reason = availabilityReason() {
            return ("", AIReviewResult(state: .modelUnavailable(reason: reason), reviewText: nil))
        }
        do {
            let session = LanguageModelSession(instructions: imageReviewInstructions)
            let response = try await session.respond(generating: GeneratedImageReview.self) {
                "Review this handwritten equation or short piece of work."
                Attachment(image)
            }
            let content = response.content
            return (content.transcription, AIReviewResult(state: .reviewed, reviewText: AITextSanitizer.run(content.answer)))
        } catch {
            return ("", AIReviewResult(state: .failed(reason: error.localizedDescription), reviewText: nil))
        }
    }

    func explain(image: CGImage) async -> (transcription: String, result: AIReviewResult) {
        if let reason = availabilityReason() {
            return ("", AIReviewResult(state: .modelUnavailable(reason: reason), reviewText: nil))
        }
        do {
            let session = LanguageModelSession(instructions: imageExplainInstructions)
            let response = try await session.respond(generating: GeneratedImageReview.self) {
                "Identify the problem in this photo, then explain step-by-step how to solve it."
                Attachment(image)
            }
            let content = response.content
            return (content.transcription, AIReviewResult(state: .reviewed, reviewText: AITextSanitizer.run(content.answer)))
        } catch {
            return ("", AIReviewResult(state: .failed(reason: error.localizedDescription), reviewText: nil))
        }
    }

    func checkAlgebra(image: CGImage) async -> (transcription: String, result: AlgebraicCheckResult) {
        if let reason = availabilityReason() {
            return ("", AlgebraicCheckResult(state: .modelUnavailable(reason: reason), verdict: nil, errors: []))
        }
        do {
            let session = LanguageModelSession(instructions: imageAlgebraCheckInstructions)
            let response = try await session.respond(generating: GeneratedImageAlgebraicCheck.self) {
                "Check the math work shown in this photo."
                Attachment(image)
            }
            let c = response.content
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
            return (c.transcription, AlgebraicCheckResult(state: state, verdict: verdict, errors: errors))
        } catch {
            return ("", AlgebraicCheckResult(state: .failed(reason: error.localizedDescription), verdict: nil, errors: []))
        }
    }

    func analyzeChemistry(image: CGImage) async -> (transcription: String, result: ChemistryResult) {
        if let reason = availabilityReason() {
            return ("", ChemistryResult(state: .modelUnavailable(reason: reason), result: nil, analysisType: nil, findings: []))
        }
        do {
            let session = LanguageModelSession(instructions: imageChemistryInstructions)
            let response = try await session.respond(generating: GeneratedImageChemistryAnalysis.self) {
                "Analyze the chemistry work shown in this photo."
                Attachment(image)
            }
            let c = response.content
            let cleanResult   = AITextSanitizer.run(c.result)
            let cleanType     = AITextSanitizer.run(c.analysisType)
            let cleanFindings = c.findings.map { AITextSanitizer.run($0) }
            return (c.transcription, ChemistryResult(state: .reviewed,
                                   result: cleanResult.isEmpty ? nil : cleanResult,
                                   analysisType: cleanType.isEmpty ? nil : cleanType,
                                   findings: cleanFindings))
        } catch {
            return ("", ChemistryResult(state: .failed(reason: error.localizedDescription),
                                   result: nil, analysisType: nil, findings: []))
        }
    }

    func extractGraphExpression(from image: CGImage) async -> (transcription: String, expression: String)? {
        guard availabilityReason() == nil else { return nil }
        do {
            let session = LanguageModelSession(instructions: imageGraphExtractInstructions)
            let response = try await session.respond(generating: GeneratedImageGraphExpression.self) {
                "Extract the plottable equation from this photo."
                Attachment(image)
            }
            let expr = response.content.expression.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !expr.isEmpty else { return nil }
            return (response.content.transcription, expr)
        } catch {
            return nil
        }
    }
}
