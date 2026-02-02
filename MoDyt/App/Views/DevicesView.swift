import SwiftUI

struct DevicesView: View {
    @Bindable var store: AppStore

    private var groupedDevices: [(DeviceGroup, [DeviceRecord])] {
        let grouped = Dictionary(grouping: store.state.devices, by: { $0.group })
        return DeviceGroup.allCases.compactMap { group in
            guard let devices = grouped[group] else { return nil }
            return (group, devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(groupedDevices, id: \.0) { group, devices in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: group.symbolName)
                            Text(group.title)
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                            Spacer()
                            Text("\(devices.count)")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 12) {
                            ForEach(devices) { device in
                                DeviceRow(
                                    device: device,
                                    onToggleFavorite: { store.send(.toggleFavorite(device.uniqueId)) },
                                    onControlChange: { key, value in
                                        store.send(.deviceControlChanged(uniqueId: device.uniqueId, key: key, value: value))
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle("Devices")
        .refreshable {
            store.send(.refreshRequested)
        }
    }
}
