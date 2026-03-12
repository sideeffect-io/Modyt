import Foundation

struct ListAuthenticationSitesEffectExecutor: Sendable {
    let listSites: @Sendable (String, String) async throws -> [AuthenticationSite]

    @concurrent
    func callAsFunction(
        email: String,
        password: String
    ) async -> AuthenticationEvent? {
        do {
            return .sitesLoaded(.success(try await listSites(email, password)))
        } catch {
            return .sitesLoaded(
                .failure(AuthenticationStoreError(message: error.localizedDescription))
            )
        }
    }
}
