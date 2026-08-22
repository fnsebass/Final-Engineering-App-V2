//
//  CircuitDiagram.swift
//  Tolerance
//
//  SwiftData model for a circuit diagram, plus supporting value types.
//  Components and wires are stored as JSON strings so SwiftData doesn't
//  need to know about the inner Codable types.
//

import SwiftData
import Foundation

// MARK: - Component type

enum CircuitComponentType: String, Codable, CaseIterable {
    case resistor   = "Resistor"
    case battery    = "Battery"
    case capacitor  = "Capacitor"
    case inductor   = "Inductor"
    case led        = "LED"
    case switchComp = "Switch"
    case ground     = "Ground"
    case voltmeter  = "Voltmeter"
    case ammeter    = "Ammeter"

    var prefix: String {
        switch self {
        case .resistor:   return "R"
        case .battery:    return "V"
        case .capacitor:  return "C"
        case .inductor:   return "L"
        case .led:        return "D"
        case .switchComp: return "S"
        case .ground:     return "GND"
        case .voltmeter:  return "VM"
        case .ammeter:    return "AM"
        }
    }

    var defaultUnit: String {
        switch self {
        case .resistor:   return "Ω"
        case .battery:    return "V"
        case .capacitor:  return "μF"
        case .inductor:   return "mH"
        case .led:        return "V"
        case .switchComp: return ""
        case .ground:     return ""
        case .voltmeter:  return "V"
        case .ammeter:    return "A"
        }
    }

    var sfIcon: String {
        switch self {
        case .resistor:   return "waveform.path"
        case .battery:    return "battery.100"
        case .capacitor:  return "square.split.2x1"
        case .inductor:   return "tornado"
        case .led:        return "lightbulb"
        case .switchComp: return "power"
        case .ground:     return "arrow.down.to.line"
        case .voltmeter:  return "gauge"
        case .ammeter:    return "gauge.with.needle"
        }
    }

    var hasValue: Bool {
        switch self {
        case .ground, .switchComp: return false
        default: return true
        }
    }
}

// MARK: - Serialisable point (CGPoint is not Codable)

struct CircuitPoint: Codable, Equatable {
    var x, y: Double
    init(_ p: CGPoint) { x = Double(p.x); y = Double(p.y) }
    init(x: Double, y: Double) { self.x = x; self.y = y }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

// MARK: - Component

struct CircuitComponent: Identifiable, Codable {
    var id: UUID = UUID()
    var type: CircuitComponentType
    var x, y: Double
    var rotation: Double = 0   // 0 / 90 / 180 / 270
    var value: Double?
    var label: String
    var isClosed: Bool = true  // switch: closed = conducting

    var position: CGPoint { CGPoint(x: x, y: y) }
    var unit: String { type.defaultUnit }

    var valueString: String {
        guard let v = value else { return "" }
        let s: String
        if v == v.rounded() && abs(v) < 100_000 { s = "\(Int(v))" }
        else { s = String(format: "%.3g", v) }
        return "\(s)\(unit)"
    }
}

// MARK: - Wire (simple two-point segment)

struct CircuitWire: Identifiable, Codable {
    var id: UUID = UUID()
    var start: CircuitPoint
    var end: CircuitPoint
}

// MARK: - SwiftData model

@Model
final class CircuitDiagram {
    var title: String
    var createdDate: Date
    var componentsJSON: String
    var wiresJSON: String

    init(title: String = "New Circuit") {
        self.title          = title
        self.createdDate    = Date()
        self.componentsJSON = "[]"
        self.wiresJSON      = "[]"
    }

    // MARK: Persistence helpers

    func loadComponents() -> [CircuitComponent] {
        (try? JSONDecoder().decode([CircuitComponent].self,
                                   from: Data(componentsJSON.utf8))) ?? []
    }

    func save(components: [CircuitComponent]) {
        componentsJSON = (try? String(
            data: JSONEncoder().encode(components), encoding: .utf8
        )) ?? "[]"
    }

    func loadWires() -> [CircuitWire] {
        (try? JSONDecoder().decode([CircuitWire].self,
                                   from: Data(wiresJSON.utf8))) ?? []
    }

    func save(wires: [CircuitWire]) {
        wiresJSON = (try? String(
            data: JSONEncoder().encode(wires), encoding: .utf8
        )) ?? "[]"
    }

    func nextLabel(for type: CircuitComponentType) -> String {
        let n = loadComponents().filter { $0.type == type }.count
        return "\(type.prefix)\(n + 1)"
    }
}
