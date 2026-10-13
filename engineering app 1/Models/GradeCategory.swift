//
//  GradeCategory.swift
//  Tolerance
//
//  A weighted grading category within a GradeClass (e.g. "Homework" worth
//  20% of the final grade). Holds the assignments that contribute to it.
//

import Foundation
import SwiftData

@Model
final class GradeCategory {
    var name: String = "New Category"

    /// This category's share of the class's final grade, 0-100.
    var weightPercent: Double = 0

    /// Manual ordering within the class.
    var orderIndex: Int = 0

    var gradeClass: GradeClass?

    @Relationship(deleteRule: .cascade, inverse: \GradeAssignment.category)
    var assignments: [GradeAssignment] = []

    init(name: String = "New Category", weightPercent: Double = 0, orderIndex: Int = 0) {
        self.name = name
        self.weightPercent = weightPercent
        self.orderIndex = orderIndex
        self.assignments = []
    }

    /// Assignments sorted for stable display order.
    var orderedAssignments: [GradeAssignment] {
        assignments.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Percentage (0-100) earned across every assignment in this category.
    /// Nil if no assignment yet has a nonzero points-possible.
    var average: Double? {
        let totalPossible = assignments.reduce(0) { $0 + $1.pointsPossible }
        guard totalPossible > 0 else { return nil }
        let totalEarned = assignments.reduce(0) { $0 + $1.pointsEarned }
        return (totalEarned / totalPossible) * 100
    }
}
