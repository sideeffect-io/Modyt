import Foundation

extension TydomConnection {
    struct Dependencies: Sendable {
        var makeSession: @Sendable (_ allowInsecureTLS: Bool, _ timeout: TimeInterval, _ credential: URLCredential?) -> URLSession
        var randomBytes: @Sendable (_ count: Int) -> [UInt8]
        var now: @Sendable () -> Date
        var fetchGatewayPassword: @Sendable (_ credentials: CloudCredentials, _ mac: String, _ session: URLSession) async throws -> String
        var invalidateSession: @Sendable (_ session: URLSession) -> Void
        var onDisconnect: @Sendable () async -> Void

        init(
            makeSession: @Sendable @escaping (_ allowInsecureTLS: Bool, _ timeout: TimeInterval, _ credential: URLCredential?) -> URLSession,
            randomBytes: @Sendable @escaping (_ count: Int) -> [UInt8],
            now: @Sendable @escaping () -> Date,
            fetchGatewayPassword: @Sendable @escaping (_ credentials: CloudCredentials, _ mac: String, _ session: URLSession) async throws -> String,
            invalidateSession: @Sendable @escaping (_ session: URLSession) -> Void = { $0.invalidateAndCancel() },
            onDisconnect: @Sendable @escaping () async -> Void = {}
        ) {
            self.makeSession = makeSession
            self.randomBytes = randomBytes
            self.now = now
            self.fetchGatewayPassword = fetchGatewayPassword
            self.invalidateSession = invalidateSession
            self.onDisconnect = onDisconnect
        }

    }
}
