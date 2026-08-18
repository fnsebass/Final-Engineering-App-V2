//
//  Page.swift
//  Tolerance
//
//  A single page of a notepad. The handwritten ink is stored as the raw
//  data representation of a PencilKit `PKDrawing`, so we don't need to import
//  PencilKit in the model layer.
//

import Foundation
import SwiftData

@Model
final class Page {
    /// Position of the page within its notepad (0-based). Used for ordering.
    var pageIndex: Int

    /// Serialized `PKDrawing` (`PKDrawing.dataRepresentation()`). Empty data
    /// represents a blank page.
    var drawingData: Data

    /// The notepad this page belongs to. Set automatically via the inverse
    /// relationship declared on `Notepad.pages`.
    var notepad: Notepad?

    init(pageIndex: Int, drawingData: Data = Data()) {
        self.pageIndex = pageIndex
        self.drawingData = drawingData
    }
}
