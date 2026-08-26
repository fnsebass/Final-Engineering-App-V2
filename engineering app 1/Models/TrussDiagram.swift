import SwiftData
import Foundation

struct TrussNode: Codable, Identifiable {
    var id: UUID = UUID()
    var x: Double
    var y: Double
    var isPin: Bool = false
    var isRoller: Bool = false
}

struct TrussMember: Codable, Identifiable {
    var id: UUID = UUID()
    var startID: UUID
    var endID: UUID
}

struct TrussLoad: Codable, Identifiable {
    var id: UUID = UUID()
    var nodeID: UUID
    var fy: Double       // positive = downward (canvas coords)
    var fx: Double = 0
    var label: String = "P"
}

@Model
final class TrussDiagram {
    var title: String
    var createdDate: Date
    var nodesJSON: String
    var membersJSON: String
    var loadsJSON: String
    var carWeight: Double

    init(title: String = "New Truss") {
        self.title       = title
        self.createdDate = Date()
        self.nodesJSON   = "[]"
        self.membersJSON = "[]"
        self.loadsJSON   = "[]"
        self.carWeight   = 50.0
    }

    func loadNodes()   -> [TrussNode]   { decode(nodesJSON) }
    func loadMembers() -> [TrussMember] { decode(membersJSON) }
    func loadLoads()   -> [TrussLoad]   { decode(loadsJSON) }
    func save(nodes:   [TrussNode])   { nodesJSON   = encode(nodes) }
    func save(members: [TrussMember]) { membersJSON = encode(members) }
    func save(loads:   [TrussLoad])   { loadsJSON   = encode(loads) }

    private func decode<T: Codable>(_ json: String) -> [T] {
        (try? JSONDecoder().decode([T].self, from: Data(json.utf8))) ?? []
    }
    private func encode<T: Codable>(_ value: [T]) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "[]"
    }
}
