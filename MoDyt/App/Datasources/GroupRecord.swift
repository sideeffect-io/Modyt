import Foundation
import DeltaDoreClient

struct GroupRecord: Codable, Identifiable, Sendable, Equatable {
    static let uniqueIdPrefix = "group_"

    let uniqueId: String
    let groupId: Int
    var name: String
    var usage: String
    var picto: String?
    var isGroupUser: Bool
    var isGroupAll: Bool
    var memberUniqueIds: [String]
    var isFavorite: Bool
    var favoriteOrder: Int?
    var dashboardOrder: Int?
    var updatedAt: Date

    var id: String { uniqueId }

    static func uniqueId(for groupId: Int) -> String {
        "\(uniqueIdPrefix)\(groupId)"
    }

    static func isGroupUniqueId(_ uniqueId: String) -> Bool {
        uniqueId.hasPrefix(uniqueIdPrefix)
    }

    static func groupId(from uniqueId: String) -> Int? {
        guard isGroupUniqueId(uniqueId) else { return nil }
        return Int(uniqueId.dropFirst(uniqueIdPrefix.count))
    }

    var resolvedGroup: DeviceGroup {
        DeviceGroup.from(usage: usage)
    }
}
