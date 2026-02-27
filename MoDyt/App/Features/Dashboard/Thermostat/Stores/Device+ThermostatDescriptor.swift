import Foundation

extension Device {
    func thermostatDescriptor() -> ThermostatStore.Descriptor? {
        guard resolvedUsage == .boiler || resolvedUsage == .thermo || hasLikelyClimatePayload else {
            return nil
        }

        let temperature = climateCurrentTemperatureSignal().map {
            ThermostatStore.Descriptor.Temperature(
                value: $0.value,
                unitSymbol: $0.unitSymbol
            )
        }

        let setpoint = climateSetpointSignal().map {
            ThermostatStore.Descriptor.Temperature(
                value: $0.value,
                unitSymbol: $0.unitSymbol
            )
        }

        let humidity = climateHumiditySignal().map {
            ThermostatStore.Descriptor.Humidity(
                value: $0.value,
                unitSymbol: $0.unitSymbol
            )
        }

        guard temperature != nil || setpoint != nil || humidity != nil else { return nil }

        return ThermostatStore.Descriptor(
            temperature: temperature,
            setpoint: setpoint,
            humidity: humidity
        )
    }
}
