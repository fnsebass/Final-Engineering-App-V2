//
//  Chapter.swift
//  Tolerance
//
//  A named grouping of notes within a Book (Folder). Deleting a chapter does
//  NOT delete its notes — they become chapter-less within the book (nullify
//  rule), mirroring Folder's non-destructive relationship to Notepad.
//

import Foundation
import SwiftData

@Model
final class Chapter {
    var name: String
    var createdDate: Date

    /// Manual ordering within the book, mirrors Page.pageIndex.
    var orderIndex: Int

    /// The book (folder) this chapter belongs to.
    var folder: Folder?

    @Relationship(deleteRule: .nullify, inverse: \Notepad.chapter)
    var notes: [Notepad]

    init(name: String = "Chapter 1", createdDate: Date = .now, orderIndex: Int = 0) {
        self.name = name
        self.createdDate = createdDate
        self.orderIndex = orderIndex
        self.notes = []
    }

    /// Notes sorted for stable display order.
    var orderedNotes: [Notepad] {
        notes.sorted { $0.createdDate < $1.createdDate }
    }
}
