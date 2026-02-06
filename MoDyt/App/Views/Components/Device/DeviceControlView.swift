import SwiftUI
import DeltaDoreClient

struct DeviceControlView: View {
    let device: DeviceRecord
    let shutterLayout: ShutterControlLayout
    let shutterRepository: ShutterRepository
    let onChange: (String, JSONValue) -> Void

    private var descriptor: DeviceControlDescriptor? {
        device.primaryControlDescriptor()
    }

    var body: some View {
        if let descriptor {
            switch descriptor.kind {
            case .toggle:
                Toggle("", isOn: Binding(
                    get: { descriptor.isOn },
                    set: { onChange(descriptor.key, .bool($0)) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)

            case .slider:
                if device.group == .shutter {
                    ShutterView(
                        device: device,
                        layout: shutterLayout,
                        shutterRepository: shutterRepository,
                        onCommand: onChange
                    )
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        Slider(value: Binding(
                            get: { descriptor.value },
                            set: { onChange(descriptor.key, .number($0)) }
                        ), in: descriptor.range)
                        Text("\(Int(descriptor.value))")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 116)
                }
            }
        } else {
            EmptyView()
        }
    }
}
