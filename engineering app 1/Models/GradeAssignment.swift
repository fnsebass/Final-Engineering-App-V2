//
//  GradeAssignment.swift
//  Tolerance
//
//  A single graded item (e.g. "Quiz 3") within a GradeCategory, scored as
//  points earned out of points possible.
//

import Foundation
import SwiftData

@Model
final class GradeAssignment {
    var name: String = "New Assignment"
    var pointsEarned: Double = 0
    var pointsPossible: Double = 100

    /// Manual ordering within the category.
    var orderIndex: Int = 0

    var category: GradeCategory?

    init(name: String = "New Assignment", pointsEarned: Double = 0, pointsPossible: Double = 100, orderIndex: Int = 0) {
        self.name = name
        self.pointsEarned = pointsEarned
        self.pointsPossible = pointsPossible
        self.orderIndex = orderIndex
    }

    /// Percentage (0-100) earned on this assignment. Nil while
    /// points-possible is zero (e.g. a freshly-added assignment).
    var percent: Double? {
        guard pointsPossible > 0 else { return nil }
        return (pointsEarned / pointsPossible) * 100
    }
}
