import DeltaDoreClient

extension Device {
    var asDeviceRecord: DeviceRecord {
        DeviceRecord(
            uniqueId: id,
            deviceId: deviceID,
            endpointId: endpointId,
            name: name,
            usage: usage,
            kind: kind,
            data: data.payloadValues,
            metadata: metadata?.payloadValues,
            isFavorite: isFavorite,
            favoriteOrder: nil,
            dashboardOrder: dashboardOrder,
            updatedAt: updatedAt
        )
    }

    var deviceID: Int {
        id
            .split(separator: "_")
            .last
            .flatMap { Int($0) } ?? 0
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    var payloadValues: [String: PayloadValue] {
        mapValues(\.payloadValue)
    }
}

extension JSONValue {
    var payloadValue: PayloadValue {
        switch self {
        case .string(let value):
            .string(value)
        case .number(let value):
            .number(value)
        case .bool(let value):
            .bool(value)
        case .object(let values):
            .object(values.mapValues(\.payloadValue))
        case .array(let values):
            .array(values.map(\.payloadValue))
        case .null:
            .null
        }
    }
}
