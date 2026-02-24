import Foundation

struct Scene: DomainType {
    let id: String
    var name: String
    var type: String
    var picto: String
    var ruleId: String?
    var payload: [String: JSONValue]
    var isFavorite: Bool
    var dashboardOrder: Int?
    var updatedAt: Date
}
