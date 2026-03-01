import Foundation

extension Device {
    func shutterControlDescriptor() -> DeviceControlDescriptor? {
        guard resolvedUsage == .shutter else { return nil }
        return sliderDescriptor(forKey: "position")
            ?? sliderDescriptor(forKey: "level")
    }

    var shutterPosition: Int? {
        guard let descriptor = shutterControlDescriptor() else {
            return nil
        }
        return Int(descriptor.value.rounded())
    }

    private func sliderDescriptor(forKey key: String) -> DeviceControlDescriptor? {
        guard let value = numericValue(forKey: key) else { return nil }
        let range = metadataRange(forKey: key) ?? 0...100
        return DeviceControlDescriptor(
            kind: .slider,
            key: key,
            isOn: value > 0,
            value: value,
            range: range
        )
    }

    private func numericValue(forKey key: String) -> Double? {
        if let value = data[key]?.numberValue {
            return value
        }
        if let raw = data[key]?.stringValue {
            return Double(raw)
        }
        return nil
    }

    private func metadataRange(forKey key: String) -> ClosedRange<Double>? {
        guard let object = metadata?[key]?.objectValue else { return nil }
        guard let minValue = object["min"]?.numberValue,
              let maxValue = object["max"]?.numberValue else { return nil }
        return minValue...maxValue
    }
}
