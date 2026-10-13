//
//  DigitalLogicSimulator.swift
//  Tolerance
//
//  Event-driven-in-spirit digital logic evaluator. "Event-driven" here means
//  the evaluator only reacts to the things that can actually change a
//  digital circuit's state — switch toggles, clock edges, and the resulting
//  ripple through combinational gates — rather than running a continuous
//  physical solve the way the analog engine does. Combinational logic is
//  settled with a bounded relaxation loop (cheap and robust for the small
//  gate counts this editor supports); sequential state (flip-flops) is
//  advanced explicitly on detected clock edges.
//

import Foundation

enum LogicLevel: Equatable {
    case low, high

    var isHigh: Bool { self == .high }
    static func from(_ bool: Bool) -> LogicLevel { bool ? .high : .low }
}

/// Persistent per-flip-flop state, owned by the caller (the editor view)
/// across simulation ticks so edges can be detected frame to frame.
struct FlipFlopState {
    var q: Bool = false
    var lastClockHigh: Bool = false
}

enum DigitalLogicSimulator {
    private static let maxRelaxationPasses = 6

    /// Evaluates every node's logic level for one simulation tick.
    /// `flipFlopStates` is updated in place when a clock edge latches a new Q.
    static func evaluate(
        components: [CircuitComponent],
        netlist: CircuitNetlist,
        clockTime: Double,
        flipFlopStates: inout [UUID: FlipFlopState]
    ) -> [CircuitNetlist.NodeID: LogicLevel] {
        var levels: [CircuitNetlist.NodeID: LogicLevel] = [:]

        func node(_ comp: CircuitComponent, _ pinID: String) -> CircuitNetlist.NodeID? {
            netlist.nodeOfPin[comp.id]?[pinID]
        }
        func level(_ comp: CircuitComponent, _ pinID: String) -> LogicLevel {
            guard let n = node(comp, pinID) else { return .low }
            return levels[n] ?? .low
        }
        func drive(_ comp: CircuitComponent, _ pinID: String, _ value: LogicLevel) {
            guard let n = node(comp, pinID) else { return }
            levels[n] = value
        }

        // Hard sources — independent of any other component's output.
        for comp in components {
            switch comp.type {
            case .ground:
                drive(comp, "A", .low)
            case .switchComp:
                let lvl: LogicLevel = .from(comp.isClosed)
                drive(comp, "A", lvl)
                drive(comp, "B", lvl)
            case .clock:
                let freq = max(comp.value ?? 1, 0.01)
                let period = 1.0 / freq
                let phase = clockTime.truncatingRemainder(dividingBy: period) / period
                drive(comp, "OUT", phase < 0.5 ? .high : .low)
            default:
                break
            }
        }

        // Relax combinational gates until stable (or the pass cap is hit —
        // circuits this editor supports are small enough that genuine
        // instability would indicate a true combinational loop, which we
        // simply let settle into whatever the last pass produced).
        for _ in 0..<maxRelaxationPasses {
            for comp in components {
                switch comp.type {
                case .notGate:
                    drive(comp, "OUT", .from(!level(comp, "A").isHigh))
                case .andGate:
                    drive(comp, "OUT", .from(level(comp, "A").isHigh && level(comp, "B").isHigh))
                case .orGate:
                    drive(comp, "OUT", .from(level(comp, "A").isHigh || level(comp, "B").isHigh))
                case .nandGate:
                    drive(comp, "OUT", .from(!(level(comp, "A").isHigh && level(comp, "B").isHigh)))
                case .norGate:
                    drive(comp, "OUT", .from(!(level(comp, "A").isHigh || level(comp, "B").isHigh)))
                case .xorGate:
                    drive(comp, "OUT", .from(level(comp, "A").isHigh != level(comp, "B").isHigh))
                case .xnorGate:
                    drive(comp, "OUT", .from(level(comp, "A").isHigh == level(comp, "B").isHigh))
                case .mux2to1:
                    let out = level(comp, "S").isHigh ? level(comp, "I1") : level(comp, "I0")
                    drive(comp, "OUT", out)
                default:
                    break
                }
            }
        }

        // Edge-triggered flip-flops, evaluated once the combinational levels
        // (including CLK and D's driving nets) have settled.
        for comp in components where comp.type == .dFlipFlop {
            let clockHigh = level(comp, "CLK").isHigh
            var state = flipFlopStates[comp.id] ?? FlipFlopState()
            if clockHigh && !state.lastClockHigh {
                state.q = level(comp, "D").isHigh
            }
            state.lastClockHigh = clockHigh
            flipFlopStates[comp.id] = state
            drive(comp, "Q", .from(state.q))
            drive(comp, "QN", .from(!state.q))
        }

        return levels
    }

    /// Per-wire level + propagation direction for rendering. Direction
    /// points away from whichever output/clock-role pin drives that wire's
    /// node (if any); undriven nets default to forward = true (arbitrary —
    /// there's nothing to animate on a LOW/undriven net anyway).
    static func wireStates(
        components: [CircuitComponent],
        wires: [CircuitWire],
        netlist: CircuitNetlist,
        levels: [CircuitNetlist.NodeID: LogicLevel]
    ) -> [UUID: (level: LogicLevel, forward: Bool)] {
        let byID = Dictionary(uniqueKeysWithValues: components.map { ($0.id, $0) })
        var result: [UUID: (level: LogicLevel, forward: Bool)] = [:]

        for wire in wires {
            guard let n = netlist.wireNode[wire.id] else { continue }
            let lvl = levels[n] ?? .low
            var forward = true

            if let pins = netlist.pinsOfNode[n] {
                for (compID, pinID) in pins {
                    guard let comp = byID[compID],
                          let pin = comp.type.pins().first(where: { $0.id == pinID }),
                          pin.role == .output || pin.role == .clock
                    else { continue }
                    let driverPos = comp.pinPosition(pin)
                    let dStart = hypot(driverPos.x - wire.start.x, driverPos.y - wire.start.y)
                    let dEnd   = hypot(driverPos.x - wire.end.x,   driverPos.y - wire.end.y)
                    forward = dStart <= dEnd
                    break
                }
            }

            result[wire.id] = (lvl, forward)
        }
        return result
    }
}
