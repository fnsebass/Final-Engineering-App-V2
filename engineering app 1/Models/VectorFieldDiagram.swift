// VectorFieldDiagram.swift — SwiftData model for Vector Field / Flow diagrams

import SwiftData
import Foundation

enum VectorFieldType: String, Codable, CaseIterable {
    case uniform = "Uniform"
    case source  = "Source / Sink"
    case vortex  = "Vortex"

    var sfIcon: String {
        switch self {
        case .uniform: return "arrow.right"
        case .source:  return "arrow.up.and.down.and.arrow.left.and.right"
        case .vortex:  return "arrow.clockwise"
        }
    }

    var hint: String {
        switch self {
        case .uniform: return "Adjust direction & magnitude with the sliders"
        case .source:  return "Tap canvas to add source (+) or sink (–)"
        case .vortex:  return "Tap canvas to add a vortex centre"
        }
    }
}

struct FieldSource: Codable, Identifiable {
    var id: UUID = UUID()
    var x: Double            // canvas coords (px)
    var y: Double
    var strength: Double     // + = source/CCW vortex  – = sink/CW vortex
}

@Model
final class VectorFieldDiagram {
    var title: String
    var createdDate: Date
    var fieldTypeRaw: String
    var sourcesJSON: String
    var uniformAngle: Double      // degrees (0=right, 90=up)
    var uniformMagnitude: Double  // display scale 0.1…3

    var fieldType: VectorFieldType {
        get { VectorFieldType(rawValue: fieldTypeRaw) ?? .uniform }
        set { fieldTypeRaw = newValue.rawValue }
    }

    init(title: String = "New Vector Field") {
        self.title            = title
        self.createdDate      = Date()
        self.fieldTypeRaw     = VectorFieldType.uniform.rawValue
        self.sourcesJSON      = "[]"
        self.uniformAngle     = 0
        self.uniformMagnitude = 1
    }

    func loadSources() -> [FieldSource] {
        (try? JSONDecoder().decode([FieldSource].self, from: Data(sourcesJSON.utf8))) ?? []
    }
    func save(sources: [FieldSource]) {
        sourcesJSON = (try? String(data: JSONEncoder().encode(sources), encoding: .utf8)) ?? "[]"
    }
}
