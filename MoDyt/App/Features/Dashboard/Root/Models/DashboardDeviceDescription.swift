import Foundation

struct DashboardDeviceDescription: Identifiable, Sendable, Equatable {
    let uniqueId: String
    let name: String
    let usage: String

    var id: String { uniqueId }

    var group: DeviceGroup {
        DeviceGroup.from(usage: usage)
    }
}
