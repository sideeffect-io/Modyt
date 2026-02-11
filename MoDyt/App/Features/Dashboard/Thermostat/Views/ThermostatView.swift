import SwiftUI

struct ThermostatView: View {
    @Environment(\.thermostatStoreFactory) private var thermostatStoreFactory

    let uniqueId: String

    var body: some View {
        WithStoreView(factory: { thermostatStoreFactory.make(uniqueId) }) { store in
            thermostatContent(store: store)
        }
    }

    @ViewBuilder
    private func thermostatContent(store: ThermostatStore) -> some View {
        if let descriptor = store.descriptor {
            VStack(spacing: 8) {
                temperatureLabel(temperature: descriptor.temperature, unitSymbol: descriptor.unitSymbol)

                if let humidity = descriptor.humidity {
                    humidityLabel(humidity: humidity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Thermostat")
            .accessibilityValue(accessibilityValue(for: descriptor))
        } else {
            Text("--")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Thermostat unavailable")
        }
    }

    @ViewBuilder
    private func temperatureLabel(
        temperature: TemperatureDescriptor?,
        unitSymbol: String?
    ) -> some View {
        if let temperature {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(temperature.value, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if let unitSymbol = unitSymbol ?? temperature.unitSymbol {
                    Text(unitSymbol)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Text("--")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func humidityLabel(humidity: HumidityDescriptor) -> some View {
        HStack(spacing: 4) {
            Text("Humidity")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            Text(humidity.value, format: .number.precision(.fractionLength(0)))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .monospacedDigit()
            if let unitSymbol = humidity.unitSymbol {
                Text(unitSymbol)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func accessibilityValue(for descriptor: ThermostatDescriptor) -> String {
        var components: [String] = []

        if let temperature = descriptor.temperature {
            let value = temperature.value.formatted(.number.precision(.fractionLength(1)))
            if let unit = descriptor.unitSymbol ?? temperature.unitSymbol {
                components.append("Current \(value) \(unit)")
            } else {
                components.append("Current \(value)")
            }
        }

        if let humidity = descriptor.humidity {
            let value = humidity.value.formatted(.number.precision(.fractionLength(0)))
            let unit = humidity.unitSymbol ?? "%"
            components.append("Humidity \(value)\(unit)")
        }

        return components.joined(separator: ", ")
    }
}
