import SwiftUI

struct AuthenticationRootView: View {
    @Environment(\.authenticationStoreFactory) private var authenticationStoreFactory
    let onAuthenticated: @MainActor () -> Void
    
    var body: some View {
        WithStoreView(factory: { authenticationStoreFactory.make(onAuthenticated) }) { store in
            content(for: store)
                .task {
                    store.send(.onAppear)
                }
        }
    }
    
    @ViewBuilder
    private func content(for store: AuthenticationStore) -> some View {
        switch store.state.phase {
        case .bootstrapping:
            BootstrappingView()
        case .login(let loginState):
            LoginView(store: store, loginState: loginState)
        case .connecting:
            ConnectingView()
        case .error(let message):
            ErrorView(message: message) {
                store.send(.retryTapped)
            }
        }
    }
}

private struct BootstrappingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Connecting to Tydom")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .glassCard(cornerRadius: 28, interactive: false)
        .padding()
    }
}

private struct ConnectingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Negotiating secure access")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .glassCard(cornerRadius: 28, interactive: false)
        .padding()
    }
}

private struct ErrorView: View {
    let message: String
    let retry: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Connection Failed")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text(message)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .glassCard(cornerRadius: 28)
        .padding()
    }
}
