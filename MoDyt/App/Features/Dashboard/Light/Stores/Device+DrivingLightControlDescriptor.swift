import Foundation

extension Device {
    func drivingLightControlDescriptor() -> DrivingLightControlDescriptor? {
        guard resolvedUsage == .light else { return nil }

        let power = lightToggleDescriptor(forKey: "on")
            ?? lightToggleDescriptor(forKey: "state")
            ?? lightFirstBoolDescriptor()

        let level = lightSliderDescriptor(forKey: "level")
            ?? lightSliderDescriptor(forKey: "position")
            ?? lightFirstNumberDescriptor()

        guard power != nil || level != nil else { return nil }

        let range = level?.range ?? 0...100
        let lowerBound = range.lowerBound
        let upperBound = range.upperBound
        let fallbackLevel = power?.isOn == true ? upperBound : lowerBound
        let rawLevel = level?.value ?? fallbackLevel
        let clampedLevel = min(max(rawLevel, lowerBound), upperBound)
        let isOn = power?.isOn ?? (clampedLevel > lowerBound)

        return DrivingLightControlDescriptor(
            powerKey: power?.key,
            levelKey: level?.key,
            isOn: isOn,
            level: clampedLevel,
            range: range
        )
    }

    private func lightSliderDescriptor(forKey key: String) -> DeviceControlDescriptor? {
        guard let value = lightNumericValue(forKey: key) else { return nil }
        let range = lightMetadataRange(forKey: key) ?? 0...100
        return DeviceControlDescriptor(
            kind: .slider,
            key: key,
            isOn: value > range.lowerBound,
            value: value,
            range: range
        )
    }

    private func lightToggleDescriptor(forKey key: String) -> DeviceControlDescriptor? {
        guard let value = data[key]?.boolValue else { return nil }
        return DeviceControlDescriptor(
            kind: .toggle,
            key: key,
            isOn: value,
            value: value ? 1 : 0,
            range: 0...1
        )
    }

    private func lightFirstBoolDescriptor() -> DeviceControlDescriptor? {
        for key in data.keys.sorted() {
            guard let value = data[key]?.boolValue else { continue }
            return DeviceControlDescriptor(
                kind: .toggle,
                key: key,
                isOn: value,
                value: value ? 1 : 0,
                range: 0...1
            )
        }
        return nil
    }

    private func lightFirstNumberDescriptor() -> DeviceControlDescriptor? {
        for key in data.keys.sorted() {
            guard let value = lightNumericValue(forKey: key) else { continue }
            let range = lightMetadataRange(forKey: key) ?? 0...100
            return DeviceControlDescriptor(
                kind: .slider,
                key: key,
                isOn: value > range.lowerBound,
                value: value,
                range: range
            )
        }
        return nil
    }

    private func lightNumericValue(forKey key: String) -> Double? {
        if let value = data[key]?.numberValue {
            return value
        }
        if let raw = data[key]?.stringValue {
            return Double(raw)
        }
        return nil
    }

    private func lightMetadataRange(forKey key: String) -> ClosedRange<Double>? {
        guard let object = metadata?[key]?.objectValue else { return nil }
        guard let minValue = object["min"]?.numberValue,
              let maxValue = object["max"]?.numberValue else { return nil }
        return minValue...maxValue
    }
}
