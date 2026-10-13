//
//  CircuitNetlist.swift
//  Tolerance
//
//  Builds the electrical graph (netlist) for a circuit diagram: every
//  component pin and wire endpoint is grouped into a "node" — a set of
//  points that are electrically the same net. Two anchors at the exact same
//  coordinate are trivially the same node (strict grid placement makes
//  fuzzy-distance matching unnecessary), but that alone isn't enough: a
//  wire's own two endpoints must also be unioned together even though they
//  usually sit at *different* coordinates — the wire itself is what makes
//  everything along its length one conductor. Hence the union-find below.
//
//  Shared by the digital simulator (Services/DigitalLogicSimulator.swift)
//  today; the analog solver in CircuitEditorView.swift keeps its own
//  independent node-merging for now and is a candidate to migrate onto this
//  same builder in a later pass.
//

import Foundation

struct CircuitNetlist {
    typealias NodeID = Int

    /// node index for a given (componentID, pinID) pair.
    let nodeOfPin: [UUID: [String: NodeID]]
    /// all (componentID, pinID) pairs that belong to a given node.
    let pinsOfNode: [NodeID: [(componentID: UUID, pinID: String)]]
    /// node index for a given wire.
    let wireNode: [UUID: NodeID]

    private enum Anchor: Hashable {
        case pin(UUID, String)
        case wireEnd(UUID, Bool)
    }

    static func build(components: [CircuitComponent], wires: [CircuitWire]) -> CircuitNetlist {
        var pointOf: [Anchor: CGPoint] = [:]

        for comp in components {
            for pin in comp.type.pins() {
                pointOf[.pin(comp.id, pin.id)] = comp.pinPosition(pin)
            }
        }
        for wire in wires {
            pointOf[.wireEnd(wire.id, true)]  = wire.start.cgPoint
            pointOf[.wireEnd(wire.id, false)] = wire.end.cgPoint
        }

        func key(_ p: CGPoint) -> String {
            "\(Int(p.x.rounded())),\(Int(p.y.rounded()))"
        }

        var parent: [String: String] = [:]
        func find(_ k: String) -> String {
            var k = k
            while let p = parent[k], p != k { k = p }
            return k
        }
        func union(_ a: String, _ b: String) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        for (_, p) in pointOf {
            let k = key(p)
            if parent[k] == nil { parent[k] = k }
        }
        // The wire itself is a single conductor, so its two endpoints are
        // the same electrical node even when their coordinates differ.
        for wire in wires {
            union(key(wire.start.cgPoint), key(wire.end.cgPoint))
        }

        var nodeIndexByRoot: [String: NodeID] = [:]
        var pinsOfNode: [NodeID: [(componentID: UUID, pinID: String)]] = [:]
        var nodeOfPin: [UUID: [String: NodeID]] = [:]
        var wireNode: [UUID: NodeID] = [:]

        func nodeIndex(forRoot root: String) -> NodeID {
            if let existing = nodeIndexByRoot[root] { return existing }
            let idx = nodeIndexByRoot.count
            nodeIndexByRoot[root] = idx
            return idx
        }

        for (anchor, p) in pointOf {
            let root = find(key(p))
            let idx = nodeIndex(forRoot: root)
            switch anchor {
            case .pin(let compID, let pinID):
                nodeOfPin[compID, default: [:]][pinID] = idx
                pinsOfNode[idx, default: []].append((compID, pinID))
            case .wireEnd(let wireID, _):
                wireNode[wireID] = idx
            }
        }

        return CircuitNetlist(nodeOfPin: nodeOfPin, pinsOfNode: pinsOfNode, wireNode: wireNode)
    }
}
