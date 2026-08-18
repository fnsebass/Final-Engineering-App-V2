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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: return "Blank"
        case .grid:  return "Grid"
        case .dots:  return "Dot grid"
        case .lined: return "Lined"
        }
    }

    var systemImage: String {
        switch self {
        case .blank: return "rectangle"
        case .grid:  return "grid"
        case .dots:  return "circle.grid.3x3"
        case .lined: return "list.bullet.rectangle"
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
