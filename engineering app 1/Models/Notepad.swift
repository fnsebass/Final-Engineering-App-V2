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

    /// Background paper style, stored as a raw string. Access via `paperStyle`.
    var paperStyleRaw: String = PaperStyle.grid.rawValue

    /// Number of grid boxes (columns) across the page width. Higher = smaller
    /// boxes. Spacing is derived from the canvas width at draw time.
    var gridColumns: Int = 16

    /// Paper (background) color as a "#RRGGBB" hex string. The pen color is
    /// always the opposite of this, so the ink is legible on any paper.
    var paperColorHex: String = "#FFFFFF"

    /// Convenience wrapper over the raw paper-style string.
    var paperStyle: PaperStyle {
        get { PaperStyle(rawValue: paperStyleRaw) ?? .blank }
        set { paperStyleRaw = newValue.rawValue }
    }

    /// The folder this notepad belongs to, or nil if it's loose in the sidebar.
    var folder: Folder?

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
