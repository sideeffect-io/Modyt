import Foundation
import DeltaDoreClient

struct SceneRecord: Codable, Identifiable, Sendable, Equatable {
    static let uniqueIdPrefix = "scene_"

    let uniqueId: String
    let sceneId: Int
    var name: String
    var type: String
    var picto: String
    var ruleId: String?
    var payload: [String: JSONValue]
    var isFavorite: Bool
    var favoriteOrder: Int?
    var dashboardOrder: Int?
    var updatedAt: Date

    var id: String { uniqueId }

    static func uniqueId(for sceneId: Int) -> String {
        "\(uniqueIdPrefix)\(sceneId)"
    }

    static func isSceneUniqueId(_ uniqueId: String) -> Bool {
        uniqueId.hasPrefix(uniqueIdPrefix)
    }
}
