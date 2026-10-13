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

// MARK: - Mode

enum CircuitMode: String, Codable, CaseIterable {
    case analog  = "Analog"
    case digital = "Digital"
}

/// Which mode(s) a component type belongs to — drives palette filtering.
enum CircuitDomain: String, Codable {
    case analog
    case digital
    case shared
}

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

    // Digital
    case andGate    = "AND Gate"
    case orGate     = "OR Gate"
    case notGate    = "NOT Gate"
    case nandGate   = "NAND Gate"
    case norGate    = "NOR Gate"
    case xorGate    = "XOR Gate"
    case xnorGate   = "XNOR Gate"
    case mux2to1    = "Multiplexer"
    case dFlipFlop  = "D Flip-Flop"
    case clock      = "Clock"

    var domain: CircuitDomain {
        switch self {
        case .resistor, .battery, .capacitor, .inductor, .voltmeter, .ammeter:
            return .analog
        case .led, .switchComp, .ground:
            return .shared
        case .andGate, .orGate, .notGate, .nandGate, .norGate, .xorGate, .xnorGate,
             .mux2to1, .dFlipFlop, .clock:
            return .digital
        }
    }

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
        case .andGate, .orGate, .notGate, .nandGate, .norGate, .xorGate, .xnorGate, .mux2to1, .dFlipFlop:
            return "U"
        case .clock:      return "CLK"
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
        case .andGate, .orGate, .notGate, .nandGate, .norGate, .xorGate, .xnorGate, .mux2to1, .dFlipFlop:
            return ""
        case .clock:      return "Hz"
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
        case .andGate:    return "arrow.triangle.merge"
        case .orGate:     return "arrow.triangle.branch"
        case .notGate:    return "circle.slash"
        case .nandGate:   return "arrow.triangle.merge"
        case .norGate:    return "arrow.triangle.branch"
        case .xorGate:    return "bolt.horizontal"
        case .xnorGate:   return "bolt.horizontal.circle"
        case .mux2to1:    return "arrow.triangle.swap"
        case .dFlipFlop:  return "memorychip"
        case .clock:      return "clock"
        }
    }

    var hasValue: Bool {
        switch self {
        case .ground, .switchComp: return false
        case .andGate, .orGate, .notGate, .nandGate, .norGate, .xorGate, .xnorGate, .mux2to1, .dFlipFlop:
            return false
        default: return true
        }
    }

    /// Pin layout in LOCAL, unrotated coordinates relative to the component
    /// center. All offsets land exactly on the canvas's 44pt grid (one grid
    /// unit per offset axis) so wires between adjacent components always
    /// connect cleanly — the same convention the original two-terminal
    /// analog parts established (±44 along the body axis).
    func pins() -> [ComponentPin] {
        switch self {
        case .ground:
            return [ComponentPin(id: "A", localOffset: CGPoint(x: 0, y: -16), role: .bidirectional)]

        case .resistor, .battery, .capacitor, .inductor, .led, .switchComp, .voltmeter, .ammeter:
            return [
                ComponentPin(id: "A", localOffset: CGPoint(x: -44, y: 0), role: .bidirectional),
                ComponentPin(id: "B", localOffset: CGPoint(x: 44, y: 0), role: .bidirectional)
            ]

        case .notGate:
            return [
                ComponentPin(id: "A",   localOffset: CGPoint(x: -44, y: 0), role: .input),
                ComponentPin(id: "OUT", localOffset: CGPoint(x: 44, y: 0),  role: .output)
            ]

        case .andGate, .orGate, .nandGate, .norGate, .xorGate, .xnorGate:
            return [
                ComponentPin(id: "A",   localOffset: CGPoint(x: -44, y: -44), role: .input),
                ComponentPin(id: "B",   localOffset: CGPoint(x: -44, y: 44),  role: .input),
                ComponentPin(id: "OUT", localOffset: CGPoint(x: 44, y: 0),    role: .output)
            ]

        case .mux2to1:
            return [
                ComponentPin(id: "I0",  localOffset: CGPoint(x: -44, y: -44), role: .input),
                ComponentPin(id: "I1",  localOffset: CGPoint(x: -44, y: 44),  role: .input),
                ComponentPin(id: "S",   localOffset: CGPoint(x: 0, y: 44),    role: .input),
                ComponentPin(id: "OUT", localOffset: CGPoint(x: 44, y: 0),    role: .output)
            ]

        case .dFlipFlop:
            return [
                ComponentPin(id: "D",   localOffset: CGPoint(x: -44, y: -44), role: .input),
                ComponentPin(id: "CLK", localOffset: CGPoint(x: -44, y: 44),  role: .clock),
                ComponentPin(id: "Q",   localOffset: CGPoint(x: 44, y: -44),  role: .output),
                ComponentPin(id: "QN",  localOffset: CGPoint(x: 44, y: 44),   role: .output)
            ]

        case .clock:
            return [ComponentPin(id: "OUT", localOffset: CGPoint(x: 44, y: 0), role: .output)]
        }
    }
}

// MARK: - Pins (generalized terminal system)

enum PinRole: String, Codable {
    case input
    case output
    case clock
    case bidirectional
}

struct ComponentPin: Identifiable {
    var id: String
    var localOffset: CGPoint
    var role: PinRole
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
    var isClosed: Bool = true  // switch: closed = conducting (analog) / logic HIGH (digital)

    var position: CGPoint { CGPoint(x: x, y: y) }
    var unit: String { type.defaultUnit }

    var valueString: String {
        guard let v = value else { return "" }
        let s: String
        if v == v.rounded() && abs(v) < 100_000 { s = "\(Int(v))" }
        else { s = String(format: "%.3g", v) }
        return "\(s)\(unit)"
    }

    /// Absolute position of one of this component's pins, taking rotation
    /// into account. Shared by the netlist builder, terminal hit-testing,
    /// and symbol rendering so there's exactly one source of truth.
    func pinPosition(_ pin: ComponentPin) -> CGPoint {
        let r = rotation * .pi / 180
        let lx = pin.localOffset.x, ly = pin.localOffset.y
        let rx = lx * cos(r) - ly * sin(r)
        let ry = lx * sin(r) + ly * cos(r)
        return CGPoint(x: x + rx, y: y + ry)
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
    var title: String = "New Circuit"
    var createdDate: Date = Date()
    var componentsJSON: String = "[]"
    var wiresJSON: String = "[]"
    var modeRaw: String = CircuitMode.analog.rawValue

    var mode: CircuitMode {
        get { CircuitMode(rawValue: modeRaw) ?? .analog }
        set { modeRaw = newValue.rawValue }
    }

    init(title: String = "New Circuit") {
        self.title          = title
        self.createdDate    = Date()
        self.componentsJSON = "[]"
        self.wiresJSON      = "[]"
        self.modeRaw        = CircuitMode.analog.rawValue
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
