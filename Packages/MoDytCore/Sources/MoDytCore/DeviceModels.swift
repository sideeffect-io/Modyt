import Foundation

public struct DeviceSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let deviceId: Int
    public let endpointId: Int
    public let name: String
    public let usage: String
    public let kind: String
    public let primaryState: Bool?
    public let primaryValueText: String?
    public let isFavorite: Bool

    public init(
        id: String,
        deviceId: Int,
        endpointId: Int,
        name: String,
        usage: String,
        kind: String,
        primaryState: Bool?,
        primaryValueText: String?,
        isFavorite: Bool
    ) {
        self.id = id
        self.deviceId = deviceId
        self.endpointId = endpointId
        self.name = name
        self.usage = usage
        self.kind = kind
        self.primaryState = primaryState
        self.primaryValueText = primaryValueText
        self.isFavorite = isFavorite
    }
}

public struct DashboardPlacement: Identifiable, Equatable, Sendable {
    public let deviceId: String
    public let row: Int
    public let column: Int
    public let span: Int

    public var id: String { deviceId }

    public init(deviceId: String, row: Int, column: Int, span: Int) {
        self.deviceId = deviceId
        self.row = row
        self.column = column
        self.span = span
    }
}
