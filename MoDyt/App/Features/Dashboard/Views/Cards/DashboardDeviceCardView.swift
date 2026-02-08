import SwiftUI
import DeltaDoreClient

struct DashboardDeviceCardView: View {
    @Environment(\.dashboardDeviceCardStoreFactory) private var dashboardDeviceCardStoreFactory
    
    let uniqueId: String
    let onToggleFavorite: () -> Void
    
    private let dashboardCardHeight: CGFloat = 194
    
    var body: some View {
        WithStoreView(factory: { dashboardDeviceCardStoreFactory.make(uniqueId) }) { store in
            Group {
                if let device = store.state.device {
                    card(for: device, store: store)
                } else {
                    placeholder
                }
            }
            .task {
                store.send(.onAppear)
            }
        }
    }
    
    private func card(for device: DeviceRecord, store: DashboardDeviceCardStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Image(systemName: device.group.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 36, height: 36)
                Spacer()
                FavoriteOrbButton(
                    isFavorite: device.isFavorite,
                    size: 32,
                    action: onToggleFavorite
                )
            }
            
            Text(device.name)
                .font(.system(.headline, design: .rounded))
                .lineLimit(1)
            
            if device.group != .shutter {
                Text(device.statusText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            controlView(for: device, store: store)
        }
        .padding(16)
        .frame(height: dashboardCardHeight, alignment: .top)
        .glassCard(cornerRadius: 22)
    }
    
    @ViewBuilder
    private func controlView(for device: DeviceRecord, store: DashboardDeviceCardStore) -> some View {
        if let descriptor = device.primaryControlDescriptor() {
            switch descriptor.kind {
            case .toggle:
                Toggle("", isOn: Binding(
                    get: { descriptor.isOn },
                    set: { store.send(.controlChanged(key: descriptor.key, value: .bool($0))) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                
            case .slider:
                if device.group == .shutter {
                    ShutterView(
                        uniqueId: uniqueId,
                        device: device,
                        layout: .regular
                    )
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        Slider(value: Binding(
                            get: { descriptor.value },
                            set: { store.send(.controlChanged(key: descriptor.key, value: .number($0))) }
                        ), in: descriptor.range)
                        Text("\(Int(descriptor.value))")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 116)
                }
            }
        }
    }
    
    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.2))
                    .frame(width: 36, height: 36)
                Spacer()
            }
            
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.2))
                .frame(width: 120, height: 16)
            
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.16))
                .frame(width: 80, height: 12)
            
            Spacer()
        }
        .padding(16)
        .frame(height: dashboardCardHeight, alignment: .top)
        .glassCard(cornerRadius: 22)
    }
}
