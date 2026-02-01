import SwiftUI
import MoDytCore

struct DeviceCardView: View {
    let device: DeviceSummary
    let isEditing: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(device.name)
                    .font(.headline)
                Spacer()
                if isEditing {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                }
            }

            Text(device.kind.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let value = device.primaryValueText {
                Text(value)
                    .font(.title3.bold())
            } else if let state = device.primaryState {
                Text(state ? "On" : "Off")
                    .font(.title3.bold())
            } else {
                Text("Ready")
                    .font(.title3.bold())
            }

            Spacer()

            toggleButton
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        if #available(iOS 26, macOS 26, *) {
            return AnyView(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.thinMaterial)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            )
        }
        return AnyView(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private var toggleButton: some View {
        let label = Text(device.primaryState == true ? "Turn Off" : "Turn On")
            .frame(maxWidth: .infinity)

        if #available(iOS 26, macOS 26, *) {
            Button(action: onToggle) {
                label
            }
            .buttonStyle(.glassProminent)
            .disabled(device.primaryState == nil || isEditing)
        } else {
            Button(action: onToggle) {
                label
            }
            .buttonStyle(.borderedProminent)
            .disabled(device.primaryState == nil || isEditing)
        }
    }
}
