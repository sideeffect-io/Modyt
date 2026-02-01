import Foundation

public struct AuthForm: Equatable, Sendable {
    public var email: String
    public var password: String
    public var expert: ExpertOptions

    public init(
        email: String = "",
        password: String = "",
        expert: ExpertOptions = ExpertOptions()
    ) {
        self.email = email
        self.password = password
        self.expert = expert
    }
}

public struct ExpertOptions: Equatable, Sendable {
    public var isEnabled: Bool
    public var connectionMode: ConnectionMode
    public var localHostOverride: String
    public var macOverride: String

    public init(
        isEnabled: Bool = false,
        connectionMode: ConnectionMode = .auto,
        localHostOverride: String = "",
        macOverride: String = ""
    ) {
        self.isEnabled = isEnabled
        self.connectionMode = connectionMode
        self.localHostOverride = localHostOverride
        self.macOverride = macOverride
    }
}

public enum ConnectionMode: String, Equatable, Sendable, CaseIterable {
    case auto
    case forceLocal
    case forceRemote
}

public struct SiteInfo: Identifiable, Equatable, Sendable {
    public struct GatewayInfo: Equatable, Sendable {
        public let mac: String
        public let name: String?

        public init(mac: String, name: String?) {
            self.mac = mac
            self.name = name
        }
    }

    public let id: String
    public let name: String
    public let gateways: [GatewayInfo]

    public init(id: String, name: String, gateways: [GatewayInfo]) {
        self.id = id
        self.name = name
        self.gateways = gateways
    }
}
