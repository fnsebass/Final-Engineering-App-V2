// BeamDiagram.swift — SwiftData model for Shear & Bending Moment diagrams

import SwiftData
import Foundation

enum SupportType: String, Codable, CaseIterable {
    case pin    = "Pin"
    case roller = "Roller"

    var sfIcon: String {
        switch self {
        case .pin:    return "triangle"
        case .roller: return "triangle.circle"
        }
    }
}

enum BeamLoadType: String, Codable, CaseIterable {
    case point       = "Point Load"
    case distributed = "Distributed"
    case moment      = "Moment"

    var sfIcon: String {
        switch self {
        case .point:       return "arrow.down"
        case .distributed: return "arrow.down.to.line"
        case .moment:      return "arrow.clockwise"
        }
    }
}

struct BeamSupport: Codable, Identifiable {
    var id: UUID = UUID()
    var position: Double    // metres from left end
    var type: SupportType
}

struct BeamLoad: Codable, Identifiable {
    var id: UUID = UUID()
    var type: BeamLoadType
    var position: Double     // metres from left
    var magnitude: Double    // kN downward +, or kN·m CW + for moment
    var endPosition: Double? // for distributed
}

@Model
final class BeamDiagram {
    var title: String
    var createdDate: Date
    var beamLength: Double
    var supportsJSON: String
    var loadsJSON: String

    init(title: String = "New Beam", length: Double = 8.0) {
        self.title       = title
        self.createdDate = Date()
        self.beamLength  = length
        let pin    = BeamSupport(position: 0,      type: .pin)
        let roller = BeamSupport(position: length, type: .roller)
        self.supportsJSON = (try? String(data: JSONEncoder().encode([pin, roller]), encoding: .utf8)) ?? "[]"
        self.loadsJSON    = "[]"
    }

    func loadSupports() -> [BeamSupport] {
        (try? JSONDecoder().decode([BeamSupport].self, from: Data(supportsJSON.utf8))) ?? []
    }
    func save(supports: [BeamSupport]) {
        supportsJSON = (try? String(data: JSONEncoder().encode(supports), encoding: .utf8)) ?? "[]"
    }
    func loadLoads() -> [BeamLoad] {
        (try? JSONDecoder().decode([BeamLoad].self, from: Data(loadsJSON.utf8))) ?? []
    }
    func save(loads: [BeamLoad]) {
        loadsJSON = (try? String(data: JSONEncoder().encode(loads), encoding: .utf8)) ?? "[]"
    }
}
