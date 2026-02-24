import Foundation

struct Group: DomainType {
    let id: String
    var name: String
    var usage: String
    var picto: String?
    var isGroupUser: Bool
    var isGroupAll: Bool
    var memberUniqueIds: [String]
    var isFavorite: Bool
    var dashboardOrder: Int?
    var updatedAt: Date

    var resolvedUsage: Usage {
        Usage.from(usage: usage)
    }
}
