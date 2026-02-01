import Foundation
import DeltaDoreClient

actor MessageIngestor {
    private var task: Task<Void, Never>?

    func start(stream: AsyncStream<TydomMessage>, database: DatabaseStore) {
        task?.cancel()
        task = Task {
            for await message in stream {
                do {
                    try await database.apply(message: message)
                } catch {
                    // Ignore individual message failures to keep stream alive.
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

extension DatabaseStore {
    func apply(message: TydomMessage) async throws {
        switch message {
        case .devices(let devices, _):
            let now = Date()
            let deviceRecords = devices.map { device in
                DeviceRecord(
                    id: device.uniqueId,
                    deviceId: device.id,
                    endpointId: device.endpointId,
                    uniqueId: device.uniqueId,
                    name: device.name,
                    usage: device.usage,
                    kind: device.kind.description,
                    data: device.data,
                    metadata: device.metadata,
                    updatedAt: now
                )
            }
            let stateRecords = devices.map { device in
                DeviceStateRecord(
                    deviceKey: device.uniqueId,
                    data: device.data,
                    updatedAt: now
                )
            }
            try await upsert(devices: deviceRecords)
            try await upsert(states: stateRecords)
        default:
            break
        }
    }
}

private extension TydomDeviceKind {
    nonisolated var description: String {
        switch self {
        case .shutter: return "shutter"
        case .window: return "window"
        case .door: return "door"
        case .garage: return "garage"
        case .gate: return "gate"
        case .light: return "light"
        case .energy: return "energy"
        case .smoke: return "smoke"
        case .boiler: return "boiler"
        case .alarm: return "alarm"
        case .weather: return "weather"
        case .water: return "water"
        case .thermo: return "thermo"
        case .other(let usage): return usage
        }
    }
}
