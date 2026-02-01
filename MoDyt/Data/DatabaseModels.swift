import Foundation
import DeltaDoreClient

nonisolated struct DeviceRecord: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let deviceId: Int
    let endpointId: Int
    let uniqueId: String
    let name: String
    let usage: String
    let kind: String
    let data: [String: JSONValue]
    let metadata: [String: JSONValue]?
    let updatedAt: Date
}

nonisolated struct DeviceStateRecord: Codable, Sendable, Equatable, Identifiable {
    let deviceKey: String
    let data: [String: JSONValue]
    let updatedAt: Date

    var id: String { deviceKey }
}

nonisolated struct FavoriteRecord: Codable, Sendable, Equatable, Identifiable {
    let deviceKey: String
    let rank: Int

    var id: String { deviceKey }
}

nonisolated struct DashboardLayoutRecord: Codable, Sendable, Equatable, Identifiable {
    let deviceKey: String
    let row: Int
    let column: Int
    let span: Int

    var id: String { deviceKey }
}

nonisolated struct DeviceSnapshot: Sendable, Equatable {
    let device: DeviceRecord
    let state: DeviceStateRecord?
    let isFavorite: Bool
}
