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
        let color = lightColorDescriptor()

        guard power != nil || level != nil || color != nil else { return nil }

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
            range: range,
            color: color
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
            guard isReservedLightColorKey(key) == false else { continue }
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

    private func lightColorDescriptor() -> DrivingLightColorDescriptor? {
        lightColorDescriptor(forKey: "colorXY")
            ?? lightColorDescriptor(forKey: "hue")
    }

    private func lightColorDescriptor(forKey key: String) -> DrivingLightColorDescriptor? {
        guard let value = lightNumericValue(forKey: key) else { return nil }
        return DrivingLightColorDescriptor(
            key: key,
            modeKey: lightColorModeKey(forColorKey: key),
            modeValue: lightColorModeValue(forColorKey: key),
            value: value,
            range: lightColorRange(forKey: key)
        )
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

    private func lightMetadataPermission(forKey key: String) -> String? {
        metadata?[key]?.objectValue?["permission"]?.stringValue?.lowercased()
    }

    private func lightColorRange(forKey key: String) -> ClosedRange<Double> {
        if let range = lightMetadataRange(forKey: key) {
            return range
        }

        if key.caseInsensitiveCompare("colorXY") == .orderedSame {
            return 0...Double(UInt32.max - 1)
        }

        if key.lowercased().contains("hue") {
            return 0...360
        }

        return 0...100
    }

    private func lightColorModeKey(forColorKey _: String) -> String? {
        guard lightMetadataPermission(forKey: "colorMode")?.contains("w") == true else {
            return nil
        }
        return "colorMode"
    }

    private func lightColorModeValue(forColorKey key: String) -> String? {
        guard lightColorModeKey(forColorKey: key) != nil else { return nil }

        if key.caseInsensitiveCompare("colorXY") == .orderedSame {
            return "XY"
        }

        if key.lowercased().contains("hue") {
            return "HS"
        }

        return data["colorMode"]?.stringValue
    }

    private func isReservedLightColorKey(_ key: String) -> Bool {
        let normalizedKey = key.lowercased()
        return normalizedKey == "colorxy"
            || normalizedKey == "colormode"
            || normalizedKey.contains("miredtemperature")
            || normalizedKey.contains("hue")
            || normalizedKey.contains("saturation")
    }
}
