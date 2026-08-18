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
//  Isolated behind a protocol so a cloud reviewer can replace it later without
//  touching the UI.
//
//  Requirements/limits (shown in UI): needs iPadOS 26+ on an Apple
//  Intelligence–capable device with Apple Intelligence on. Best for
//  straightforward algebra; may struggle with long derivations.
//

import Foundation
import FoundationModels

// MARK: - Result types (UI-facing, platform neutral)

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

// MARK: - Guided-generation schema

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
}

extension EquationReviewService {
    var isAvailable: Bool { availabilityReason() == nil }
}

// MARK: - On-device implementation

struct OnDeviceEquationReviewService: EquationReviewService {

    private let reviewInstructions = """
    You are a careful math tutor for handwritten engineering equations. The \
    input was recognized from handwriting and may contain small errors. Reply in \
    under 80 words, plain text: if it's incomplete, complete/solve it; if it has \
    an algebraic error, name it and give the correction; if correct, say so \
    briefly. If unreadable or not math, say you couldn't interpret it.
    """

    private let stepInstructions = """
    You are a meticulous math grader. Break the student's handwritten work into \
    its individual steps in the order written. Judge each step on its own: set \
    isCorrect to true only if that step follows correctly. For an incorrect step, \
    set isCorrect to false and give a short note explaining the mistake. Keep the \
    step text close to what was written. Give a one-sentence overall verdict.
    """

    private let explainInstructions = """
    You are a patient engineering tutor. Explain, from start to finish, how to \
    solve the given problem, teaching the method so the student could solve a \
    similar one themselves. Use short numbered steps, keep it under 180 words, \
    plain text with no markdown headers. If the input isn't a solvable problem, \
    say what more you'd need.
    """

    func availabilityReason() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence, which the on-device model requires."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to enable on-device AI."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading or getting ready. Please try again shortly."
        case .unavailable(let other):
            return "The on-device model is currently unavailable (\(other))."
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
            let session = LanguageModelSession(instructions: reviewInstructions)
            let response = try await session.respond(to: "Equation: \(trimmed)")
            return AIReviewResult(state: .reviewed, reviewText: response.content)
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
            let session = LanguageModelSession(instructions: stepInstructions)
            let response = try await session.respond(to: "Work to review:\n\(trimmed)",
                                                     generating: GeneratedStepReview.self)
            let content = response.content
            let steps = content.steps.map {
                ReviewedStep(text: $0.text, isCorrect: $0.isCorrect, note: $0.note)
            }
            return StepReviewResult(state: .reviewed, steps: steps, verdict: content.verdict)
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
            let session = LanguageModelSession(instructions: explainInstructions)
            let response = try await session.respond(to: "Problem: \(trimmed)")
            return AIReviewResult(state: .reviewed, reviewText: response.content)
        } catch {
            return AIReviewResult(state: .failed(reason: error.localizedDescription), reviewText: nil)
        }
    }

    /// Trims and returns the input, or nil if it's empty.
    private func prepared(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
