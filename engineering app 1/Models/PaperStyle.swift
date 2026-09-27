//
//  PaperStyle.swift
//  Tolerance
//
//  The background paper styles a notepad can use, plus the millimetre→points
//  conversion for grid spacing. Purely a visual/background concern — the grid
//  is never part of the PencilKit drawing data.
//

import Foundation
import CoreGraphics

enum PaperStyle: String, CaseIterable, Identifiable {
    case blank
    case grid
    case dots
    case lined
    /// Ten ruled, checkbox-prefixed lines followed by an "Other Reminders"
    /// header and continued ruled space. Used only by the permanent
    /// Reminders notepad (`Notepad.isReminders`) — never offered as a
    /// regular paper style, so it's excluded from `selectable`.
    case checklist

    var id: String { rawValue }

    /// Paper styles offered in the app's paper-style pickers. `.checklist`
    /// is deliberately excluded — it's only ever set programmatically for
    /// the permanent Reminders notepad.
    static var selectable: [PaperStyle] { allCases.filter { $0 != .checklist } }

    var displayName: String {
        switch self {
        case .blank:     return "Blank"
        case .grid:      return "Grid"
        case .dots:      return "Dot grid"
        case .lined:     return "Lined"
        case .checklist: return "Checklist"
        }
    }

    var systemImage: String {
        switch self {
        case .blank:     return "rectangle"
        case .grid:      return "grid"
        case .dots:      return "circle.grid.3x3"
        case .lined:     return "list.bullet.rectangle"
        case .checklist: return "checklist"
        }
    }
}

enum CanvasMetrics {
    /// Approximate physical points-per-millimetre on iPad. iPad displays are
    /// ~264 ppi at @2x, i.e. ~132 points per inch; there is no public API for
    /// the exact physical density, so this is the standard iPad approximation.
    static let pointsPerMM: CGFloat = 132.0 / 25.4  // ≈ 5.2 pt/mm  → 5 mm ≈ 26 pt

    static func points(fromMM millimetres: Double) -> CGFloat {
        CGFloat(millimetres) * pointsPerMM
    }
}
