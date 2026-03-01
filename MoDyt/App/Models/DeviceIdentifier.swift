import Foundation
import DeltaDoreClient

struct DeviceIdentifier: Sendable, Hashable, Codable {
    let deviceId: Int
    let endpointId: Int

    init(deviceId: Int, endpointId: Int) {
        self.deviceId = deviceId
        self.endpointId = endpointId
    }

    init(_ identifier: TydomDeviceIdentifier) {
        self.init(deviceId: identifier.deviceId, endpointId: identifier.endpointId)
    }

    init?(storageKey: String) {
        let components = storageKey.split(separator: ":")
        guard components.count == 2,
              let deviceId = Int(components[0]),
              let endpointId = Int(components[1]) else {
            return nil
        }
        self.init(deviceId: deviceId, endpointId: endpointId)
    }

    var asDeltaDoreIdentifier: TydomDeviceIdentifier {
        TydomDeviceIdentifier(deviceId: deviceId, endpointId: endpointId)
    }

    var storageKey: String {
        "\(deviceId):\(endpointId)"
    }
}
