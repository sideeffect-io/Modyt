import Foundation

struct DeviceTypeSection: Sendable, Equatable {
    let usage: Usage
    let items: [Device]
}

enum DeviceListProjector {
    nonisolated static func sections(from devices: [Device]) -> [DeviceTypeSection] {
        let grouped = Dictionary(grouping: devices, by: \.resolvedUsage)
        return Usage.allCases.compactMap { usage in
            guard let values = grouped[usage] else { return nil }
            let sorted = values.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return DeviceTypeSection(usage: usage, items: sorted)
        }
    }
}
