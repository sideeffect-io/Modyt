import SwiftUI

struct DevicesView: View {
    @Bindable var store: RuntimeStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(store.state.groupedDevices) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: section.group.symbolName)
                            Text(section.group.title)
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                            Spacer()
                            Text("\(section.devices.count)")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 8) {
                            ForEach(section.devices) { device in
                                DeviceRow(
                                    device: device,
                                    shutterRepository: store.shutterRepository,
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
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .navigationTitle("Devices")
        .refreshable {
            store.send(.refreshRequested)
        }
    }
}
