//
//  DrawingTool.swift
//  Tolerance
//

import Foundation

enum ShapeKind: String, CaseIterable, Equatable {
    case rectangle, circle, oval, arrow, triangle

    var systemImage: String {
        switch self {
        case .rectangle: return "rectangle"
        case .circle:    return "circle"
        case .oval:      return "oval"
        case .arrow:     return "arrow.right"
        case .triangle:  return "triangle"
        }
    }

    var displayName: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .circle:    return "Circle"
        case .oval:      return "Oval"
        case .arrow:     return "Arrow"
        case .triangle:  return "Triangle"
        }
    }
}

enum DrawingTool: Equatable {
    case pen
    case marker
    case highlighter
    case straightLine
    case eraser
    case lasso
    case shape
}
