//
//  GradeClass.swift
//  Tolerance
//
//  A single class/course in the Grade Calculator. Holds weighted grading
//  categories (e.g. "Homework", "Tests"), each of which holds assignments.
//

import Foundation
import SwiftData

@Model
final class GradeClass {
    var name: String = "New Class"
    var createdDate: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \GradeCategory.gradeClass)
    var categories: [GradeCategory] = []

    init(name: String = "New Class", createdDate: Date = .now) {
        self.name = name
        self.createdDate = createdDate
        self.categories = []
    }

    /// Categories sorted for stable display order.
    var orderedCategories: [GradeCategory] {
        categories.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Weighted average across categories that have at least one graded
    /// assignment, re-normalized over just those categories' weights so an
    /// empty category (no assignments yet) doesn't drag the grade down.
    /// Nil until at least one assignment has been entered anywhere.
    var overallGrade: Double? {
        let graded = orderedCategories.compactMap { category -> (average: Double, weight: Double)? in
            guard let average = category.average else { return nil }
            return (average, category.weightPercent)
        }
        let totalWeight = graded.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let weightedSum = graded.reduce(0) { $0 + $1.average * $1.weight }
        return weightedSum / totalWeight
    }
}
