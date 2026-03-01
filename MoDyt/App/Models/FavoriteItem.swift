import Foundation

enum FavoriteType: Sendable, Equatable, Hashable, Codable {
    case device(identifier: DeviceIdentifier)
    case scene(sceneId: String)
    case group(groupId: String, memberIdentifiers: [DeviceIdentifier])
    
    var id: String {
        switch self {
        case .device(identifier: let id):
            return "device:\(id.deviceId):\(id.endpointId)"
        case .scene(sceneId: let id):
            return "scene:\(id)"
        case .group(groupId: let id, memberIdentifiers: _):
            return "group:\(id)"
        }
    }

    var sceneOrGroupId: String? {
        switch self {
        case .device:
            return nil
        case .scene(let id):
            return id
        case .group(let id, _):
            return id
        }
    }

    var deviceIdentifier: DeviceIdentifier? {
        guard case .device(let identifier) = self else { return nil }
        return identifier
    }
}

struct FavoriteItem: Sendable, Equatable {
    let name: String
    let usage: Usage
    let type: FavoriteType
    let order: Int
    let controlKind: FavoriteControlKind
    let rawUsage: String

    init(
        name: String,
        usage: Usage,
        type: FavoriteType,
        order: Int,
        controlKind: FavoriteControlKind? = nil,
        rawUsage: String? = nil
    ) {
        self.name = name
        self.usage = usage
        self.type = type
        self.order = order
        self.controlKind = controlKind ?? FavoriteControlKind.from(usage: usage)
        self.rawUsage = rawUsage ?? usage.rawValue
    }
    
    var id: String {
        type.id
    }
    
    var group: DeviceGroup {
        DeviceGroup.from(usage: rawUsage)
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
        type.sceneOrGroupId ?? ""
    }

    var controlGroupId: String? {
        if case .group(let id, _) = type {
            return id
        }
        return nil
    }

    var controlDeviceIdentifier: DeviceIdentifier? {
        type.deviceIdentifier
    }

    var shutterIdentifiers: [DeviceIdentifier] {
        guard group == .shutter else { return [] }

        switch type {
        case .device(let identifier):
            return [identifier]
        case .group(_, let memberIdentifiers):
            return memberIdentifiers
        case .scene:
            return []
        }
    }
}
