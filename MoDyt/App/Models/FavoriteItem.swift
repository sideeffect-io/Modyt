import Foundation

enum FavoriteType: Sendable, Equatable, Hashable, Codable {
    case device(deviceId: String)
    case scene(sceneId: String)
    case group(groupId: String, memberUniqueIds: [String])
    
    var id: String {
        switch self {
        case .device(deviceId: let id):
            return "device:\(id)"
        case .scene(sceneId: let id):
            return "scene:\(id)"
        case .group(groupId: let id, memberUniqueIds: _):
            return "group:\(id)"
        }
    }

    var entityId: String {
        switch self {
        case .device(let id):
            return id
        case .scene(let id):
            return id
        case .group(let id, _):
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
    
    var group: DeviceGroup {
        DeviceGroup.from(usage: usage.rawValue)
    }

    var isScene: Bool {
        if case .scene = type {
            return true
        }
        return false
    }

    var isGroup: Bool {
        if case .group = type {
            return true
        }
        return false
    }

    var sceneExecutionUniqueId: String {
        type.entityId
    }

    var controlUniqueId: String {
        type.entityId
    }

    var shutterUniqueIds: [String] {
        guard group == .shutter else { return [] }

        switch type {
        case .device(let deviceID):
            return [deviceID]
        case .group(_, let memberUniqueIds):
            return memberUniqueIds
        case .scene:
            return []
        }
    }
}
