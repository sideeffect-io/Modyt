import SwiftUI

struct ThermostatView: View {
    @Environment(\.thermostatStoreFactory) private var thermostatStoreFactory

    let identifier: DeviceIdentifier

    var body: some View {
        WithStoreView(factory: { thermostatStoreFactory.make(identifier) }) { store in
            thermostatContent(store: store)
        }
    }

    @ViewBuilder
    private func thermostatContent(store: ThermostatStore) -> some View {
        if let state = store.state {
            VStack(spacing: 8) {
                temperatureLabel(
                    temperature: state.temperature,
                    setpoint: state.setpoint
                )

                if let humidity = state.humidity {
                    humidityLabel(humidity: humidity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Thermostat")
            .accessibilityValue(accessibilityValue(for: state))
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
        temperature: ThermostatStore.Descriptor.Temperature?,
        setpoint: ThermostatStore.Descriptor.Temperature?
    ) -> some View {
        if let temperature {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(temperature.value, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if let unitSymbol = temperature.unitSymbol {
                    Text(unitSymbol)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else if let setpoint {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Set")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(setpoint.value, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if let unitSymbol = setpoint.unitSymbol {
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

    private func humidityLabel(humidity: ThermostatStore.Descriptor.Humidity) -> some View {
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

    private func accessibilityValue(for viewState: ThermostatStore.Descriptor) -> String {
        var components: [String] = []

        if let temperature = viewState.temperature {
            let value = temperature.value.formatted(.number.precision(.fractionLength(1)))
            if let unit = temperature.unitSymbol {
                components.append("Current \(value) \(unit)")
            } else {
                components.append("Current \(value)")
            }
        }

        if let setpoint = viewState.setpoint {
            let value = setpoint.value.formatted(.number.precision(.fractionLength(1)))
            if let unit = setpoint.unitSymbol {
                components.append("Setpoint \(value) \(unit)")
            } else {
                components.append("Setpoint \(value)")
            }
        }

        if let humidity = viewState.humidity {
            let value = humidity.value.formatted(.number.precision(.fractionLength(0)))
            let unit = humidity.unitSymbol ?? "%"
            components.append("Humidity \(value)\(unit)")
        }

        return components.joined(separator: ", ")
    }
}
