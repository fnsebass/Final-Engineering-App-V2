//
//  Folder.swift
//  Tolerance
//
//  A named folder that groups notepads in the sidebar. Notepads are added by
//  dragging them onto the folder. Deleting a folder does NOT delete its
//  notepads — they simply become loose again (nullify rule).
//

import Foundation
import SwiftData

@Model
final class Folder {
    var name: String
    var createdDate: Date

    /// Cover color as a "#RRGGBB" hex string, chosen from BookTheme's muted
    /// palette. Defaults to the palette's first color.
    var coverColorHex: String = "#5B7C99"

    /// SF Symbol name shown on the book's cover, chosen by the user.
    var iconName: String = "book.closed.fill"

    @Relationship(deleteRule: .nullify, inverse: \Notepad.folder)
    var notepads: [Notepad]

    @Relationship(deleteRule: .cascade, inverse: \Chapter.folder)
    var chapters: [Chapter]

    init(name: String = "New Folder", createdDate: Date = .now) {
        self.name = name
        self.createdDate = createdDate
        self.notepads = []
        self.chapters = []
    }

    /// Chapters sorted for stable display order.
    var orderedChapters: [Chapter] {
        chapters.sorted { $0.orderIndex < $1.orderIndex }
    }
}
