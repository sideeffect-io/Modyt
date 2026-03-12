import Foundation

struct ConnectStoredAuthenticationEffectExecutor: Sendable {
    let connectStored: @Sendable () async throws -> Void

    @concurrent
    func callAsFunction() async -> AuthenticationEvent? {
        do {
            try await connectStored()
            return .connectionSucceeded
        } catch {
            return .connectionFailed(error.localizedDescription)
        }
    }
}
