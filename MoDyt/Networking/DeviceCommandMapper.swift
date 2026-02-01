import Foundation
import DeltaDoreClient
import MoDytCore

nonisolated enum DeviceCommandMapper {
    nonisolated static func makeToggleCommand(
        from device: DeviceSummary,
        data: [String: JSONValue]
    ) -> TydomCommand? {
        let key = resolveToggleKey(from: device, data: data)
        guard let key else { return nil }

        if let boolValue = resolvedBool(for: key, data: data) {
            let toggled = !boolValue
            return TydomCommand.putDevicesData(
                deviceId: String(device.deviceId),
                endpointId: String(device.endpointId),
                name: key,
                value: toggled ? .bool(true) : .bool(false)
            )
        }

        if let numeric = resolvedNumber(for: key, data: data) {
            let next = numeric <= 0 ? 100 : 0
            return TydomCommand.putDevicesData(
                deviceId: String(device.deviceId),
                endpointId: String(device.endpointId),
                name: key,
                value: .int(Int(next))
            )
        }

        return nil
    }

    nonisolated private static func resolveToggleKey(
        from device: DeviceSummary,
        data: [String: JSONValue]
    ) -> String? {
        let preferred = ["on", "open", "state", "level", "position", "power"]
        for key in preferred where data[key] != nil {
            return key
        }

        switch device.kind {
        case "light":
            return "on"
        case "shutter", "window", "door", "gate", "garage":
            return "position"
        case "alarm":
            return "state"
        default:
            return nil
        }
    }

    nonisolated private static func resolvedBool(
        for key: String,
        data: [String: JSONValue]
    ) -> Bool? {
        guard let value = data[key] else { return nil }
        if let boolValue = value.boolValue { return boolValue }
        if let numberValue = value.numberValue { return numberValue > 0 }
        if let stringValue = value.stringValue?.lowercased() {
            if ["on", "true", "open", "enabled"].contains(stringValue) { return true }
            if ["off", "false", "closed", "disabled"].contains(stringValue) { return false }
        }
        return nil
    }

    nonisolated private static func resolvedNumber(
        for key: String,
        data: [String: JSONValue]
    ) -> Double? {
        guard let value = data[key] else { return nil }
        return value.numberValue
    }
}
