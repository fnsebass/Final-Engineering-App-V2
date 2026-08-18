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

    @Relationship(deleteRule: .nullify, inverse: \Notepad.folder)
    var notepads: [Notepad]

    init(name: String = "New Folder", createdDate: Date = .now) {
        self.name = name
        self.createdDate = createdDate
        self.notepads = []
    }
}
