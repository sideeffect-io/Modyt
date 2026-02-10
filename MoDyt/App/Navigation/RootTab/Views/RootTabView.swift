import SwiftUI

struct RootTabView: View {
    @Environment(\.rootTabStoreFactory) private var rootTabStoreFactory

    let isAppActive: Bool
    let onDidDisconnect: @MainActor () -> Void

    var body: some View {
        WithStoreView(
            factory: { rootTabStoreFactory.make(onDidDisconnect) },
            content: { store in
                tabContent()
                    .task {
                        store.send(.onStart)
                        store.send(.setAppActive(isAppActive))
                    }
                    .onChange(of: isAppActive) { _, newValue in
                        store.send(.setAppActive(newValue))
                    }
            }
        )
    }

    @ViewBuilder
    private func tabContent() -> some View {
        TabView {
            Tab("Dashboard", systemImage: "square.grid.2x2") {
                NavigationStack {
                    TabBackgroundContainer {
                        DashboardView()
                            .hideChromeBackgroundForMobileTabs()
                    }
                }
                .clearNavigationContainerBackground()
            }

            Tab("Devices", systemImage: "square.stack.3d.up") {
                NavigationStack {
                    TabBackgroundContainer {
                        DevicesView()
                            .hideChromeBackgroundForMobileTabs()
                    }
                }
                .clearNavigationContainerBackground()
            }

            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    TabBackgroundContainer {
                        SettingsView()
                            .navigationTitle("Settings")
                            .hideChromeBackgroundForMobileTabs()
                    }
                }
                .clearNavigationContainerBackground()
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func hideChromeBackgroundForMobileTabs() -> some View {
        #if os(iOS)
        self
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .tabBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func clearNavigationContainerBackground() -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            containerBackground(.clear, for: .navigation)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

private struct TabBackgroundContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            AppBackgroundView()
            content
        }
    }
}
