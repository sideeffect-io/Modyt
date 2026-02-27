import Foundation

extension Device {
    struct HeatPumpGatewayValues: Sendable, Equatable {
        let temperature: Double
        let setPoint: Double
    }

    func heatPumpGatewayValues() -> HeatPumpGatewayValues? {
        guard isHeatPumpCandidate else { return nil }
        guard let temperature = climateCurrentTemperatureSignal()?.value,
              let setPoint = climateSetpointSignal()?.value else {
            return nil
        }
        return HeatPumpGatewayValues(
            temperature: temperature,
            setPoint: setPoint
        )
    }

    func heatPumpSetpointKey() -> String? {
        guard isHeatPumpCandidate else { return nil }
        return climateSetpointSignal()?.key
    }

    private var isHeatPumpCandidate: Bool {
        if controlKind == .heatPump {
            return true
        }

        return resolvedUsage == .boiler
            || resolvedUsage == .thermo
            || hasLikelyHeatPumpPayload
            || hasLikelyClimatePayload
    }
}
