import Foundation

enum LightGatewayCommandValue: Sendable, Equatable {
    case bool(Bool)
    case int(Int)
}

struct LightGatewayCommandRequest: Sendable, Equatable {
    let deviceId: DeviceIdentifier
    let signalName: String
    let value: LightGatewayCommandValue
}
