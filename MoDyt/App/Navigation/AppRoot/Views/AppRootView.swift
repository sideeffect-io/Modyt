import SwiftUI

struct AppRootView: View {
    var body: some View {
        WithStoreView(
            store: AppRootStore(),
        ) { store in
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                content(for: store)
            }
        }
    }

    @ViewBuilder
    private func content(for store: AppRootStore) -> some View {
        switch store.state.route {
        case .authentication:
            AuthenticationRootView(onAuthenticated: {
                store.send(.authenticated)
            })

        case .runtime:
            MainView(
                onDisconnected: {
                    store.send(.didDisconnect)
                }
            )
        }
    }
}
