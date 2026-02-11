import Foundation

struct DashboardDeviceDescription: Identifiable, Sendable, Equatable {
    let uniqueId: String
    let name: String
    let usage: String
    let resolvedGroup: DeviceGroup?

    init(
        uniqueId: String,
        name: String,
        usage: String,
        resolvedGroup: DeviceGroup? = nil
    ) {
        self.uniqueId = uniqueId
        self.name = name
        self.usage = usage
        self.resolvedGroup = resolvedGroup
    }

    var id: String { uniqueId }

    var group: DeviceGroup {
        resolvedGroup ?? DeviceGroup.from(usage: usage)
    }
}
