import SwiftUI

struct DevicesView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(store.state.groupedDevices) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: section.group.symbolName)
                            Text(section.group.title)
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                            Spacer()
                            Text("\(section.devices.count)")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 12) {
                            ForEach(section.devices) { device in
                                let targetStep = store.state.shutterTargetStep(for: device)
                                let actualStep = store.state.shutterActualStep(for: device)
                                DeviceRow(
                                    device: device,
                                    shutterTargetStep: targetStep,
                                    shutterActualStep: actualStep,
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
