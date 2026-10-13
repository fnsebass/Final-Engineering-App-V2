//
//  AIPracticeGenerator.swift
//  Tolerance
//
//  Generates an AI Practice worksheet: a notepad whose page shows each
//  question as scroll-synced typed text (drawn by GridContentView, the same
//  layer that draws grid lines and the Reminders checklist — see PaperStyle
//  .aiPractice) followed by blank space for the student to write their
//  answer in Pencil ink. Uses Apple's on-device FoundationModels framework
//  (LanguageModelSession + @Generable), the same mechanism CircuitEditorView
//  uses for AI circuit generation — no API key or network required.
//
//  Grading (see `grade(image:question:)` below) also runs entirely on-device
//  via FoundationModels' multimodal (image + text) prompting, rather than
//  Gemini Vision — no external API, so no daily rate limit.
//
//  Layout constants here are shared with GridContentView's .aiPractice
//  drawing case (PencilCanvasView.swift) and with the Submit/grading crop in
//  NotepadEditorView — all three must agree on where things sit on the page.
//

import Foundation
import UIKit
import SwiftData
import FoundationModels

@Generable
struct GeneratedPracticeSet {
    @Guide(description: "Practice questions for the given class and unit, in order from easier to harder. Plain text, no numbering, no markdown.")
    var questions: [String]
}

enum AIPracticeGenerationError: LocalizedError {
    case modelUnavailable
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "On-device AI is unavailable on this device."
        case .emptyResult:
            return "The AI didn't return any questions. Try again."
        }
    }
}

enum AIPracticeGenerator {

    /// Fixed page width (points) — must agree with GridContentView's
    /// .aiPractice drawing and with the Submit/grading crop width.
    static let contentWidth: CGFloat = 900
    static let sidePadding: CGFloat = 40
    static let questionFont = UIFont.systemFont(ofSize: 22, weight: .semibold)

    private static let gapAboveAnswer: CGFloat = 14
    private static let answerAreaHeight: CGFloat = 260
    private static let gapBetweenQuestions: CGFloat = 36
    private static let topMargin: CGFloat = 40

    static var isAIAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// The numbered label text actually drawn on the page for a question —
    /// shared so height measurement (here) and drawing (GridContentView)
    /// never disagree.
    static func labelText(number: Int, question: String) -> String {
        "\(number). \(question)"
    }

    private static func labelHeight(_ label: String) -> CGFloat {
        let width = contentWidth - sidePadding * 2
        let bounding = (label as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: questionFont],
            context: nil
        )
        return ceil(bounding.height)
    }

    /// Generates the question text via the on-device model, then builds and
    /// inserts a fully laid-out practice notepad into `context`. Returns the
    /// new notepad, already inserted (caller just needs to open it).
    @MainActor
    static func generate(className: String, unitName: String, questionCount: Int,
                         in context: ModelContext) async throws -> Notepad {
        guard isAIAvailable else { throw AIPracticeGenerationError.modelUnavailable }

        let instructions = """
        You are an expert teacher preparing a practice worksheet for a student.

        Generate exactly \(questionCount) practice questions for the class "\(className)", \
        specifically covering the unit "\(unitName)".

        Rules:
        - Each question must be answerable with a short written or numeric answer a student \
        would write by hand in the blank space below it.
        - Order questions from easier to harder.
        - Each question must be self-contained — never reference "the previous question" or \
        "question 3".
        - Plain text only. No markdown, no asterisks, no LaTeX delimiters, no numbering (numbering \
        is added separately).
        - Use Unicode math symbols where relevant: ∫ √ × ÷ → ≤ ≥ ∞ ∂ π ² ³ Σ ± ≈
        """

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: "Generate \(questionCount) practice questions.",
            generating: GeneratedPracticeSet.self
        )

        let questions = response.content.questions
        guard !questions.isEmpty else { throw AIPracticeGenerationError.emptyResult }

        let notepad = Notepad(title: "\(className) — \(unitName)")
        notepad.isAIPractice = true
        notepad.aiPracticeClassName = className
        notepad.aiPracticeUnitName = unitName
        notepad.paperStyleRaw = PaperStyle.aiPractice.rawValue
        context.insert(notepad)

        let page = Page(pageIndex: 0)
        page.notepad = notepad
        context.insert(page)

        var y: CGFloat = topMargin
        for (index, question) in questions.enumerated() {
            let number = index + 1
            let label = labelText(number: number, question: question)
            let textHeight = labelHeight(label)

            let questionYStart = y
            y += textHeight + gapAboveAnswer
            let answerStart = y
            let answerEnd = y + answerAreaHeight

            let record = AIPracticeQuestion(
                text: question,
                orderIndex: index,
                questionYStart: questionYStart,
                answerYStart: answerStart,
                answerYEnd: answerEnd
            )
            record.notepad = notepad
            context.insert(record)

            y = answerEnd + gapBetweenQuestions
        }

        return notepad
    }

    /// Builds the plain layout snapshot CanvasWorkspace hands down to
    /// PencilCanvasView/GridContentView for drawing.
    static func layout(for notepad: Notepad) -> [AIPracticeQuestionLayout] {
        notepad.orderedAIPracticeQuestions.map { q in
            AIPracticeQuestionLayout(
                number: q.orderIndex + 1,
                text: q.text,
                questionYStart: CGFloat(q.questionYStart),
                answerYEnd: CGFloat(q.answerYEnd)
            )
        }
    }

    // MARK: - Grading (on-device, multimodal)

    private static let gradingInstructions = """
    You are grading a student's handwritten answer to a specific practice question. The \
    attached image shows only the student's handwritten work in the blank space below the \
    question — it does not include the question text itself, which is given separately.

    If the image is blank or shows no legible handwriting, mark it incorrect and say no \
    answer was written.
    """

    /// Grades a single AI Practice question's handwritten answer using the
    /// on-device model's multimodal (image + text) prompting — no network
    /// call and no external API rate limit.
    ///
    /// - Parameters:
    ///   - image: Just the student's answer ink for this question, cropped
    ///     directly from the page's PKDrawing (see AIPracticeQuestion).
    ///   - question: The original question text, for grading context.
    @available(iOS 27.0, *)
    static func grade(image: CGImage, question: String) async throws -> (isCorrect: Bool, feedback: String) {
        guard isAIAvailable else { throw AIPracticeGenerationError.modelUnavailable }

        let session = LanguageModelSession(instructions: gradingInstructions)
        let response = try await session.respond(generating: GradedAnswer.self) {
            "Question: \(question)"
            Attachment(image)
        }
        return (response.content.isCorrect, response.content.feedback)
    }
}

@Generable
struct GradedAnswer {
    @Guide(description: "Whether the handwritten answer correctly answers the question.")
    var isCorrect: Bool

    @Guide(description: "One or two sentences. If correct, briefly confirm why. If incorrect, state the specific error and the correct answer.")
    var feedback: String
}
