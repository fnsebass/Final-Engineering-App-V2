//
//  HandwritingCorrection.swift
//  Tolerance
//
//  Persists one learned association between a raw OCR fragment and the
//  character(s) the user confirmed it should be.  Applied automatically
//  before every graph / solve pass so the AI sees cleaner input over time.
//

import SwiftData
import Foundation

@Model
final class HandwritingCorrection {
    /// What OCR produced (e.g. "1og", "B", "u").
    var ocrFragment: String
    /// What the user confirmed it to be (e.g. "log", "8", "v").
    var correctedFragment: String
    /// A short snippet of the surrounding equation shown in the memory panel.
    var exampleContext: String
    var dateAdded: Date
    /// Incremented each time this correction is applied automatically.
    var useCount: Int

    init(ocrFragment: String, correctedFragment: String, exampleContext: String = "") {
        self.ocrFragment = ocrFragment
        self.correctedFragment = correctedFragment
        self.exampleContext = exampleContext
        self.dateAdded = Date()
        self.useCount = 0
    }
}
