import SwiftUI
import MoDytCore

struct DevicesListView: View {
    @Bindable var store: AppStore
    @State private var searchText = ""

    var body: some View {
        List {
            ForEach(groupedDevices.keys.sorted(), id: \.self) { group in
                Section(group) {
                    ForEach(groupedDevices[group] ?? []) { device in
                        DeviceRowView(device: device) {
                            store.send(.deviceAction(device))
                        } onFavorite: { isFavorite in
                            store.send(.favoriteToggled(device.id, isFavorite))
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Devices")
    }

    private var filteredDevices: [DeviceSummary] {
        let devices = store.state.devices
        guard searchText.isEmpty == false else { return devices }
        return devices.filter { device in
            device.name.localizedStandardContains(searchText) ||
            device.kind.localizedStandardContains(searchText)
        }
    }

    private var groupedDevices: [String: [DeviceSummary]] {
        Dictionary(grouping: filteredDevices, by: { $0.kind.capitalized })
    }
}

private struct DeviceRowView: View {
    let device: DeviceSummary
    let onToggle: () -> Void
    let onFavorite: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                Text(device.primaryValueText ?? device.kind.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if device.primaryState != nil {
                Button(device.primaryState == true ? "Off" : "On") {
                    onToggle()
                }
                .buttonStyle(.bordered)
            }

            Button {
                onFavorite(!device.isFavorite)
            } label: {
                Image(systemName: device.isFavorite ? "star.fill" : "star")
            }
            .buttonStyle(.plain)
        }
    }
}
