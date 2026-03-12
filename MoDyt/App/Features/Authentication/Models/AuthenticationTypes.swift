import Foundation

enum AuthenticationFlowStatus: Sendable, Equatable {
    case connectWithStoredCredentials
    case connectWithNewCredentials
}

struct AuthenticationSite: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let gatewayCount: Int
}
