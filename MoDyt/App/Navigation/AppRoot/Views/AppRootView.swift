import SwiftUI

struct AppRootView: View {
    @Environment(\.appCoordinatorStoreFactory) private var appCoordinatorStoreFactory

    var body: some View {
        WithStoreView(factory: appCoordinatorStoreFactory.make ) { store in
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
            RootTabView(
                onDidDisconnect: {
                    store.send(.didDisconnect)
                }
            )
        }
    }
}
