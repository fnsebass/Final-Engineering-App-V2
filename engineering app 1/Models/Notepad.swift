//
//  Notepad.swift
//  Tolerance
//
//  A Notepad is a single document the user works in. It has a title, some
//  dates for sorting/display, and one or more pages of handwritten ink.
//

import Foundation
import SwiftData

@Model
final class Notepad {
    /// The user-visible name shown on the home screen.
    var title: String

    /// When the notepad was first created.
    var createdDate: Date

    /// When the notepad was last edited. Used to sort the home screen so the
    /// most recently touched notepad appears first.
    var lastEditedDate: Date

    /// The pages that belong to this notepad. Deleting a notepad also deletes
    /// its pages (cascade). SwiftData does not guarantee ordering, so we sort
    /// by `pageIndex` when reading via `orderedPages`.
    @Relationship(deleteRule: .cascade, inverse: \Page.notepad)
    var pages: [Page]

    // MARK: - Appearance settings (per notepad)

    /// Spacing between grid lines, in points.
    var gridSpacing: Double = 32

    /// Whether to draw the background grid.
    var showsGrid: Bool = true

    /// Paper (background) color as a "#RRGGBB" hex string. The pen color is
    /// always the opposite of this, so the ink is legible on any paper.
    var paperColorHex: String = "#FFFFFF"

    init(title: String = "Untitled Notepad", createdDate: Date = .now) {
        self.title = title
        self.createdDate = createdDate
        self.lastEditedDate = createdDate
        self.pages = []
    }

    /// Pages sorted in display order.
    var orderedPages: [Page] {
        pages.sorted { $0.pageIndex < $1.pageIndex }
    }

    /// Mark the notepad as edited "now" so it sorts to the top of the home screen.
    func markEdited() {
        lastEditedDate = .now
    }
}
