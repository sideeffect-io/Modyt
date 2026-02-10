import SwiftUI

struct TemperatureView: View {
    @Environment(\.temperatureStoreFactory) private var temperatureStoreFactory

    let uniqueId: String

    var body: some View {
        WithStoreView(factory: { temperatureStoreFactory.make(uniqueId) }) { store in
            valueContent(descriptor: store.descriptor)
        }
    }

    @ViewBuilder
    private func valueContent(descriptor: TemperatureDescriptor?) -> some View {
        if let descriptor {
            valueLabel(descriptor: descriptor)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Temperature")
                .accessibilityValue(accessibilityValue(for: descriptor))
        } else {
            Text("--")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Temperature unavailable")
        }
    }

    private func valueLabel(descriptor: TemperatureDescriptor) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(descriptor.value, format: .number.precision(.fractionLength(1)))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()

            if let unitSymbol = descriptor.unitSymbol {
                Text(unitSymbol)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func accessibilityValue(for descriptor: TemperatureDescriptor) -> String {
        let valueText = descriptor.value.formatted(.number.precision(.fractionLength(1)))
        if let unitSymbol = descriptor.unitSymbol {
            return "\(valueText) \(unitSymbol)"
        }
        return valueText
    }
}
