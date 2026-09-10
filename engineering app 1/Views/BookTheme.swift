//
//  BookTheme.swift
//  Tolerance
//
//  Curated cover colors and icons a user can assign to a Book (Folder).
//  Colors are deliberately muted/desaturated rather than bright/saturated,
//  so a shelf of books reads as "colorful but calm" rather than neon.
//

import SwiftUI

struct BookColorOption: Identifiable {
    let name: String
    let hex: String
    var id: String { hex }
}

enum BookTheme {
    static let coverPalette: [BookColorOption] = [
        BookColorOption(name: "Slate Blue",   hex: "#5B7C99"),
        BookColorOption(name: "Sage",         hex: "#7A8F6E"),
        BookColorOption(name: "Terracotta",   hex: "#B76F4B"),
        BookColorOption(name: "Mustard",      hex: "#C7A045"),
        BookColorOption(name: "Plum",         hex: "#8B6A8E"),
        BookColorOption(name: "Muted Teal",   hex: "#588C88"),
        BookColorOption(name: "Dusty Rose",   hex: "#B98787"),
        BookColorOption(name: "Olive",        hex: "#8B8F5A"),
        BookColorOption(name: "Slate Gray",   hex: "#7A828C"),
        BookColorOption(name: "Burnt Orange", hex: "#B9702F")
    ]

    /// Assigns new books a color by cycling through the palette, so a
    /// freshly-created library doesn't default every book to the same hue.
    static func nextColorHex(existingCount: Int) -> String {
        coverPalette[existingCount % coverPalette.count].hex
    }

    /// All book-shaped, so a cover reads as an actual book rather than a
    /// generic subject icon (atom, gear, flask, etc.).
    static let icons: [String] = [
        "book.closed.fill", "book.fill", "books.vertical.fill",
        "character.book.closed.fill", "book.closed", "bookmark.fill"
    ]
}
