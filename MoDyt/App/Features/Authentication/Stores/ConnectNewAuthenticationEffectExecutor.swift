import Foundation

struct ConnectNewAuthenticationEffectExecutor: Sendable {
    let connectNew: @Sendable (String, String, Int?) async throws -> Void

    @concurrent
    func callAsFunction(
        email: String,
        password: String,
        siteIndex: Int?
    ) async -> AuthenticationEvent? {
        do {
            try await connectNew(email, password, siteIndex)
            return .connectionSucceeded
        } catch {
            return .connectionFailed(error.localizedDescription)
        }
    }
}
