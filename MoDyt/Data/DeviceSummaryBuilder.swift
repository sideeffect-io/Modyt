import Foundation
import DeltaDoreClient
import MoDytCore

nonisolated enum DeviceSummaryBuilder {
    nonisolated static func build(
        snapshots: [DeviceSnapshot],
        favorites: [FavoriteRecord],
        layout: [DashboardLayoutRecord]
    ) -> [DeviceSummary] {
        _ = layout
        let favoriteSet = Set(favorites.map { $0.deviceKey })
        return snapshots.map { snapshot in
            let data = snapshot.state?.data ?? snapshot.device.data
            let primaryState = extractPrimaryState(from: data)
            let primaryValueText = extractPrimaryValueText(from: data)

            return DeviceSummary(
                id: snapshot.device.id,
                deviceId: snapshot.device.deviceId,
                endpointId: snapshot.device.endpointId,
                name: snapshot.device.name,
                usage: snapshot.device.usage,
                kind: snapshot.device.kind,
                primaryState: primaryState,
                primaryValueText: primaryValueText,
                isFavorite: favoriteSet.contains(snapshot.device.id)
            )
        }
    }

    nonisolated private static func extractPrimaryState(from data: [String: JSONValue]) -> Bool? {
        let boolKeys = ["on", "open", "state", "status", "active", "enabled"]
        for key in boolKeys {
            if let value = data[key]?.boolValue {
                return value
            }
        }
        if let value = data["level"]?.numberValue {
            return value > 0
        }
        return nil
    }

    nonisolated private static func extractPrimaryValueText(from data: [String: JSONValue]) -> String? {
        if let value = data["temperature"]?.numberValue {
            return String(format: "%.1f°", value)
        }
        if let value = data["temp"]?.numberValue {
            return String(format: "%.1f°", value)
        }
        if let value = data["level"]?.numberValue {
            return "Level \(Int(value))%"
        }
        if let value = data["position"]?.numberValue {
            return "\(Int(value))%"
        }
        if let value = data["battery"]?.numberValue {
            return "Battery \(Int(value))%"
        }
        return nil
    }
}
