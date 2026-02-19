import Foundation

enum DashboardFavoriteSource: String, Sendable, Equatable, Codable {
    case device
    case scene
    case group
}

struct DashboardDeviceDescription: Identifiable, Sendable, Equatable {
    let uniqueId: String
    let name: String
    let usage: String
    let resolvedGroup: DeviceGroup?
    let dashboardOrder: Int?
    let source: DashboardFavoriteSource
    let sceneType: String?
    let scenePicto: String?
    let memberUniqueIds: [String]

    init(
        uniqueId: String,
        name: String,
        usage: String,
        resolvedGroup: DeviceGroup? = nil,
        dashboardOrder: Int? = nil,
        source: DashboardFavoriteSource = .device,
        sceneType: String? = nil,
        scenePicto: String? = nil,
        memberUniqueIds: [String] = []
    ) {
        self.uniqueId = uniqueId
        self.name = name
        self.usage = usage
        self.resolvedGroup = resolvedGroup
        self.dashboardOrder = dashboardOrder
        self.source = source
        self.sceneType = sceneType
        self.scenePicto = scenePicto
        self.memberUniqueIds = memberUniqueIds
    }

    var id: String { uniqueId }

    var isScene: Bool {
        source == .scene
    }

    var group: DeviceGroup {
        resolvedGroup ?? DeviceGroup.from(usage: usage)
    }

    var shutterUniqueIds: [String] {
        guard group == .shutter else { return [] }

        switch source {
        case .device:
            return [uniqueId]
        case .group:
            return memberUniqueIds
        case .scene:
            return []
        }
    }
}
