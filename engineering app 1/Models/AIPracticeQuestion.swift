//
//  AIPracticeQuestion.swift
//  Tolerance
//
//  One generated question on an AI Practice notepad. The question text is
//  drawn directly by GridContentView (PencilCanvasView.swift) — the same
//  scroll-synced drawing layer used for grid lines and the Reminders
//  checklist — never as PencilKit ink and never as a CanvasPhoto (which is
//  positioned in the fixed viewport, not the scrollable page content, so it
//  wouldn't track scrolling correctly for a multi-question worksheet).
//
//  Grading crops just the blank answer-space y-range out of the page's
//  PKDrawing directly (PKDrawing.image(from:scale:) renders from the stored
//  drawing data, not the live view), so it works regardless of scroll
//  position and never includes the (separately drawn) question text.
//

import Foundation
import CoreGraphics
import SwiftData

@Model
final class AIPracticeQuestion {
    var text: String = ""

    /// Manual ordering top-to-bottom on the page.
    var orderIndex: Int = 0

    /// Page-local y where this question's typed text label begins.
    var questionYStart: Double = 0

    /// Blank-space y-range (page-local points) reserved for the student's
    /// handwritten answer to this question.
    var answerYStart: Double = 0
    var answerYEnd: Double = 0

    var notepad: Notepad?

    /// Set once "Submit" has graded this question. `nil` until first graded.
    var isCorrect: Bool?
    var gradeFeedback: String?

    init(text: String, orderIndex: Int, questionYStart: Double, answerYStart: Double, answerYEnd: Double) {
        self.text = text
        self.orderIndex = orderIndex
        self.questionYStart = questionYStart
        self.answerYStart = answerYStart
        self.answerYEnd = answerYEnd
    }
}

/// Plain (non-model) snapshot of a question's text + layout, handed down to
/// PencilCanvasView/GridContentView for drawing — keeps the UIKit drawing
/// layer decoupled from SwiftData.
struct AIPracticeQuestionLayout {
    let number: Int
    let text: String
    let questionYStart: CGFloat
    let answerYEnd: CGFloat
}
