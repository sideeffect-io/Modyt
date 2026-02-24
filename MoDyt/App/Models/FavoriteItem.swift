import Foundation

enum FavoriteType: Sendable, Equatable, Hashable, Codable {
    case device(deviceId: String)
    case scene(sceneId: String)
    case group(groupId: String, memberUniqueIds: [String])
    
    var id: String {
        switch self {
        case .device(deviceId: let id):
            return id
        case .scene(sceneId: let id):
            return id
        case .group(groupId: let id, memberUniqueIds: _):
            return id
        }
    }
}

struct FavoriteItem: Sendable, Equatable {
    let name: String
    let usage: Usage
    let type: FavoriteType
    let order: Int
    
    var id: String {
        type.id
    }
}
