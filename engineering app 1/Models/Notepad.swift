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

    /// The folder (book) this notepad belongs to, or nil if it's loose in the sidebar.
    var folder: Folder?

    /// The chapter this note belongs to within its book, or nil if it's
    /// filed in a book but not yet assigned to a chapter. Kept in sync with
    /// `folder` via `assign(to:)` rather than derived, so Home's existing
    /// folder-based filtering/drag-drop logic needs no changes.
    var chapter: Chapter?

    /// Files this note into `chapter` and its parent book in one step.
    func assign(to chapter: Chapter) {
        self.chapter = chapter
        self.folder = chapter.folder
    }

    /// Expressions previously plotted from this note, most recent last.
    /// Surfaced as the "Graphs" section of the notebook side panel.
    var graphHistory: [String] = []

    /// True only for the single permanent "Reminders" notepad reachable from
    /// Home's sidebar. Excluded from Home's grid and the loose-notes list so
    /// it doesn't show up as an ordinary, deletable note.
    var isReminders: Bool = false

    init(title: String = "New Note", createdDate: Date = .now) {
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
