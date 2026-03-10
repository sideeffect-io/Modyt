import Foundation

enum LightGatewayCommandValue: Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case string(String)
}

struct LightGatewayCommandRequest: Sendable, Equatable {
    let deviceId: DeviceIdentifier
    let signalName: String
    let value: LightGatewayCommandValue
}

struct LightGatewayColorCommandRequest: Sendable, Equatable {
    let deviceId: DeviceIdentifier
    let signalName: String
    let value: LightGatewayCommandValue
    let colorModeSignalName: String?
    let colorModeValue: String?
}

enum SingleLightGatewayCommand: Sendable, Equatable {
    case data(LightGatewayCommandRequest)
    case color(LightGatewayColorCommandRequest)
}
