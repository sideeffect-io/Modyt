import Foundation

struct Device: DomainType {
    let id: DeviceIdentifier
    let deviceId: Int
    let endpointId: Int
    var name: String
    var usage: String
    var kind: String
    var data: [String: JSONValue]
    var metadata: [String: JSONValue]?
    var isFavorite: Bool
    var dashboardOrder: Int?
    var shutterTargetPosition: Int? = nil
    var updatedAt: Date

    var resolvedUsage: Usage {
        Usage.from(usage: usage)
    }
}

struct RepositoryDeviceTypeSection: Sendable, Equatable {
    let usage: Usage
    let items: [Device]
}
