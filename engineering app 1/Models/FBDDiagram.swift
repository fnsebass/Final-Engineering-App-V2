// FBDDiagram.swift — SwiftData model for Free Body Diagrams

import SwiftData
import Foundation

enum FBDForceType: String, Codable, CaseIterable {
    case applied  = "Applied"
    case weight   = "Weight"
    case normal   = "Normal"
    case friction = "Friction"
    case tension  = "Tension"

    var defaultAngle: Double {
        switch self {
        case .applied:  return 0
        case .weight:   return 270
        case .normal:   return 90
        case .friction: return 180
        case .tension:  return 45
        }
    }

    var sfIcon: String {
        switch self {
        case .applied:  return "arrow.right.circle.fill"
        case .weight:   return "arrow.down.circle.fill"
        case .normal:   return "arrow.up.circle.fill"
        case .friction: return "arrow.left.circle.fill"
        case .tension:  return "arrow.up.right.circle.fill"
        }
    }

    var defaultHex: String {
        switch self {
        case .applied:  return "#007AFF"
        case .weight:   return "#FF3B30"
        case .normal:   return "#34C759"
        case .friction: return "#FF9500"
        case .tension:  return "#AF52DE"
        }
    }
}

struct FBDForce: Codable, Identifiable {
    var id: UUID = UUID()
    var label: String
    var magnitude: Double    // Newtons
    var angle: Double        // degrees: 0=right 90=up 180=left 270=down
    var type: FBDForceType
    var colorHex: String?    // nil = use type default

    var fx: Double { magnitude * cos(angle * .pi / 180) }
    var fy: Double { magnitude * sin(angle * .pi / 180) }

    var resolvedColorHex: String { colorHex ?? type.defaultHex }
}

// Ramp shape placed on the canvas.
// Pure-math; CGPoint extensions live in the iOS-only view file.
struct FBDRamp: Codable, Identifiable {
    var id: UUID = UUID()
    var x: Double           // left anchor x (canvas px)
    var y: Double           // left anchor y (canvas px)
    var angle: Double       // degrees above horizontal (slope up-right)
    var length: Double      // px along slope

    // Y of the ramp surface at a given canvas x position. Returns nil if x is outside the ramp.
    func surfaceY(at px: Double) -> Double? {
        let rad  = angle * .pi / 180
        let x1   = x, x2 = x + length * cos(rad)
        let minX = min(x1, x2), maxX = max(x1, x2)
        guard px >= minX - 2 && px <= maxX + 2 else { return nil }
        let t = (x2 - x1) == 0 ? 0.0 : (px - x1) / (x2 - x1)
        return y - t * length * sin(rad)
    }

    // Outward normal direction (away from ramp surface, pointing up) in screen coords (y down).
    // n = (-sin θ, -cos θ)
    var normalDX: Double { -sin(angle * .pi / 180) }
    var normalDY: Double { -cos(angle * .pi / 180) }
}

@Model
final class FBDDiagram {
    var title: String
    var createdDate: Date
    var forcesJSON: String
    // Optional so SwiftData can add these columns via lightweight migration on existing stores.
    var rampsJSON:  String?
    var objectX: Double?
    var objectY: Double?

    init(title: String = "New FBD") {
        self.title       = title
        self.createdDate = Date()
        self.forcesJSON  = "[]"
        self.rampsJSON   = "[]"
        self.objectX     = 0
        self.objectY     = 0
    }

    func loadForces() -> [FBDForce] {
        (try? JSONDecoder().decode([FBDForce].self, from: Data(forcesJSON.utf8))) ?? []
    }
    func save(forces: [FBDForce]) {
        forcesJSON = (try? String(data: JSONEncoder().encode(forces), encoding: .utf8)) ?? "[]"
    }
    func loadRamps() -> [FBDRamp] {
        guard let json = rampsJSON else { return [] }
        return (try? JSONDecoder().decode([FBDRamp].self, from: Data(json.utf8))) ?? []
    }
    func save(ramps: [FBDRamp]) {
        rampsJSON = (try? String(data: JSONEncoder().encode(ramps), encoding: .utf8)) ?? "[]"
    }
}
