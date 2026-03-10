import Foundation

extension Device {
    func energyConsumptionDescriptor() -> EnergyConsumptionStore.Descriptor? {
        guard resolvedUsage == .energy || resolvedUsage == .other else {
            return nil
        }

        for key in Self.preferredDirectEnergyConsumptionKeys {
            if let descriptor = makeEnergyConsumptionDescriptor(forKey: key) {
                return descriptor
            }
        }

        if let descriptor = aggregatedEnergyDistributionDescriptor() {
            return descriptor
        }

        for key in Self.preferredCumulativeEnergyConsumptionKeys {
            if let descriptor = makeEnergyConsumptionDescriptor(forKey: key) {
                return descriptor
            }
        }

        let rankedLikelyKeys = data.keys
            .filter(Self.isLikelyEnergyConsumptionKey)
            .sorted { lhs, rhs in
                let lhsPriority = Self.energyConsumptionPriority(forKey: lhs)
                let rhsPriority = Self.energyConsumptionPriority(forKey: rhs)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }

        for key in rankedLikelyKeys {
            guard Self.isLikelyEnergyConsumptionKey(key) else { continue }
            guard let descriptor = makeEnergyConsumptionDescriptor(forKey: key) else { continue }
            return descriptor
        }

        return nil
    }

    private func aggregatedEnergyDistributionDescriptor() -> EnergyConsumptionStore.Descriptor? {
        let componentKeys = data.keys
            .filter(Self.isEnergyDistributionComponentKey)
            .sorted()

        guard componentKeys.count >= 2 else {
            return nil
        }

        let rawTotal = componentKeys
            .compactMap(numericEnergyValue(forKey:))
            .reduce(0, +)

        guard rawTotal > 0 else {
            return nil
        }

        return EnergyConsumptionStore.Descriptor(
            key: "energyDistrib_TOTAL",
            value: rawTotal / 1_000,
            range: Self.defaultEnergyConsumptionRange,
            unitSymbol: "kWh"
        )
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

    private static func isEnergyDistributionComponentKey(_ key: String) -> Bool {
        let normalized = key.uppercased()
        guard normalized.hasPrefix("ENERGYDISTRIB_") else {
            return false
        }

        return normalized.hasSuffix("_HEATING")
            || normalized.hasSuffix("_COOLING")
            || normalized.hasSuffix("_HOTWATER")
            || normalized.hasSuffix("_OUTLET")
            || normalized.hasSuffix("_OTHER")
    }

    private static func energyConsumptionPriority(forKey key: String) -> Int {
        let normalized = key.lowercased()

        if normalized == "consumption" || normalized.contains("daily") {
            return 0
        }
        if normalized.contains("energyhisto") && normalized.contains("total") {
            return 10
        }
        if normalized.contains("energydistrib") && normalized.contains("total") {
            return 20
        }
        if normalized.contains("energyindex") && normalized.contains("total") {
            return 30
        }
        if normalized.contains("energyhisto") {
            return 40
        }
        if normalized.contains("energyindex") {
            return 50
        }
        if normalized.contains("energydistrib") {
            return 60
        }
        if normalized.contains("consumption") || normalized.contains("kwh") {
            return 70
        }
        return 80
    }

    private static let preferredDirectEnergyConsumptionKeys = [
        "dailyConsumption",
        "dailyEnergy",
        "consumption",
        "energyHisto_ELEC_TOTAL",
        "energyHisto_ELEC",
        "energyHisto",
        "energyDistrib_ELEC_TOTAL"
    ]

    private static let preferredCumulativeEnergyConsumptionKeys = [
        "energyIndex_ELEC_TOTAL",
        "energyIndex_ELEC",
        "energyTotIndexWatt",
        "energyIndexTi1",
        "energyIndex",
        "energy"
    ]

    // 36 kVA (typical residential max in France) used continuously for 24h ~= 864 kWh/day.
    private static let defaultEnergyConsumptionRange: ClosedRange<Double> = 0...864
}
