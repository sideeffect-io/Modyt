import Foundation

extension Device {
    func energyConsumptionDescriptor() -> EnergyConsumptionStore.Descriptor? {
        guard resolvedUsage == .energy || resolvedUsage == .other else {
            return nil
        }

        for key in Self.preferredEnergyConsumptionKeys {
            if let descriptor = makeEnergyConsumptionDescriptor(forKey: key) {
                return descriptor
            }
        }

        for key in data.keys.sorted() {
            guard Self.isLikelyEnergyConsumptionKey(key) else { continue }
            guard let descriptor = makeEnergyConsumptionDescriptor(forKey: key) else { continue }
            return descriptor
        }

        return nil
    }

    private func makeEnergyConsumptionDescriptor(forKey key: String) -> EnergyConsumptionStore.Descriptor? {
        guard let rawValue = numericEnergyValue(forKey: key) else { return nil }

        let unit = energyConsumptionUnit(forKey: key)
        return EnergyConsumptionStore.Descriptor(
            key: key,
            value: rawValue * unit.multiplier,
            range: Self.defaultEnergyConsumptionRange,
            unitSymbol: unit.symbol
        )
    }

    private func numericEnergyValue(forKey key: String) -> Double? {
        if let value = data[key]?.numberValue {
            return value
        }
        if let raw = data[key]?.stringValue {
            return Double(raw)
        }
        return nil
    }

    private struct EnergyConsumptionUnit {
        let symbol: String
        let multiplier: Double
    }

    private func energyConsumptionUnit(forKey key: String) -> EnergyConsumptionUnit {
        let metadataObject = metadata?[key]?.objectValue
        let metadataCandidates = [
            metadataObject?["unit"]?.stringValue,
            metadataObject?["unity"]?.stringValue,
            metadataObject?["symbol"]?.stringValue,
            metadataObject?["uom"]?.stringValue
        ]

        if let rawUnit = metadataCandidates.compactMap({ $0 }).first,
           let unit = normalizedEnergyConsumptionUnit(rawUnit) {
            return unit
        }

        let dataCandidates = [
            data["\(key)_unit"]?.stringValue,
            data["\(key)Unit"]?.stringValue,
            data["energyUnit"]?.stringValue,
            data["consumptionUnit"]?.stringValue,
            data["unit"]?.stringValue
        ]

        if let rawUnit = dataCandidates.compactMap({ $0 }).first,
           let unit = normalizedEnergyConsumptionUnit(rawUnit) {
            return unit
        }

        return EnergyConsumptionUnit(symbol: "kWh", multiplier: 1)
    }

    private func normalizedEnergyConsumptionUnit(_ raw: String) -> EnergyConsumptionUnit? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let canonical = trimmed
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")

        switch canonical {
        case "na", "n/a", "none", "null", "-":
            return nil
        case "kwh", "kilowatthour", "kilowatthours":
            return EnergyConsumptionUnit(symbol: "kWh", multiplier: 1)
        case "wh", "watthour", "watthours":
            return EnergyConsumptionUnit(symbol: "kWh", multiplier: 0.001)
        case "mwh", "megawatthour", "megawatthours":
            return EnergyConsumptionUnit(symbol: "kWh", multiplier: 1000)
        default:
            return EnergyConsumptionUnit(symbol: trimmed, multiplier: 1)
        }
    }

    private static func isLikelyEnergyConsumptionKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        if normalized.contains("energyinstant") {
            return false
        }

        return normalized.contains("energyindex")
            || normalized.contains("energyhisto")
            || normalized.contains("consumption")
            || normalized.contains("kwh")
            || normalized.contains("energy")
    }

    private static let preferredEnergyConsumptionKeys = [
        "energyIndex_ELEC",
        "energyIndex",
        "energyHisto_ELEC",
        "energyHisto",
        "consumption",
        "energy"
    ]

    // 36 kVA (typical residential max in France) used continuously for 24h ~= 864 kWh/day.
    private static let defaultEnergyConsumptionRange: ClosedRange<Double> = 0...864
}
