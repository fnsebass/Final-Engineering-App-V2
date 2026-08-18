//
//  EquationReviewService.swift
//  Tolerance
//
//  Phase 6b: on-device AI review of an equation using Apple's Foundation
//  Models framework.
//
//  This is deliberately isolated behind the `EquationReviewService` protocol so
//  a cloud-based reviewer could be substituted later (roadmap item) without
//  changing any UI code.
//
//  Requirements & limitations (surface these to the user in the UI):
//   • Needs iPadOS/iOS 26+ on an Apple Intelligence–capable device with Apple
//     Intelligence turned on. No special entitlement or account is required.
//   • The on-device model is best at straightforward algebra; it can struggle
//     with long multi-step derivations.
//

import Foundation
import FoundationModels

/// The outcome of an AI review attempt.
struct AIReviewResult {
    enum State: Equatable {
        case reviewed                       // model produced a review
        case modelUnavailable(reason: String)
        case skipped(reason: String)
        case failed(reason: String)
    }

    let state: State
    /// The model's review text, present only when `state == .reviewed`.
    let reviewText: String?

    /// A short, always-shown honesty label for the UI.
    static let disclaimer = "On-device AI — best for straightforward equations; may struggle with complex derivations. Always double-check."
}

/// Abstraction over "something that can review an equation". Swap the concrete
/// type to move review off-device in the future.
protocol EquationReviewService {
    func availabilityReason() -> String?
    func review(equation: String) async -> AIReviewResult
}

extension EquationReviewService {
    var isAvailable: Bool { availabilityReason() == nil }
}

/// Reviews equations using the on-device system language model.
struct OnDeviceEquationReviewService: EquationReviewService {

    private let instructions = """
    You are a careful math tutor for handwritten engineering equations. The \
    equation you receive was recognized from handwriting, so it may contain \
    small recognition errors. Respond briefly (under 80 words), in plain text \
    with no markdown headers:
    1. If the equation is INCOMPLETE (for example it ends with "=" or is missing \
    a side), complete or solve it and show the result.
    2. If it contains an ALGEBRAIC ERROR, name the mistake and give the corrected \
    equation.
    3. If it appears correct, say so in one short sentence.
    If the input is unreadable or is not mathematics, say you couldn't interpret it.
    """

    /// Returns nil when the model is ready to use, otherwise a user-facing
    /// explanation of why it isn't.
    func availabilityReason() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence, which the on-device model requires."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to enable on-device AI review."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading or getting ready. Please try again shortly."
        case .unavailable(let other):
            return "The on-device model is currently unavailable (\(other))."
        }
    }

    func review(equation: String) async -> AIReviewResult {
        let trimmed = equation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AIReviewResult(state: .skipped(reason: "Nothing was recognized to review."), reviewText: nil)
        }
        if let reason = availabilityReason() {
            return AIReviewResult(state: .modelUnavailable(reason: reason), reviewText: nil)
        }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: "Equation: \(trimmed)")
            return AIReviewResult(state: .reviewed, reviewText: response.content)
        } catch {
            return AIReviewResult(state: .failed(reason: error.localizedDescription), reviewText: nil)
        }
    }
}
