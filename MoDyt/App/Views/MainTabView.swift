import SwiftUI

struct MainTabView: View {
    @Bindable var store: AppStore

    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "square.grid.2x2") {
                NavigationStack {
                    TabBackgroundContainer {
                        DashboardView(store: store)
                            .toolbarBackground(.hidden, for: .navigationBar)
                            .toolbarBackground(.hidden, for: .tabBar)
                    }
                }
                .clearNavigationContainerBackground()
            }

            Tab("Devices", systemImage: "square.stack.3d.up") {
                NavigationStack {
                    TabBackgroundContainer {
                        DevicesView(store: store)
                            .toolbarBackground(.hidden, for: .navigationBar)
                            .toolbarBackground(.hidden, for: .tabBar)
                    }
                }
                .clearNavigationContainerBackground()
            }

            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    TabBackgroundContainer {
                        SettingsView(store: store)
                            .navigationTitle("Settings")
                            .toolbarBackground(.hidden, for: .navigationBar)
                            .toolbarBackground(.hidden, for: .tabBar)
                    }
                }
                .clearNavigationContainerBackground()
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func clearNavigationContainerBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(.clear, for: .navigation)
        } else {
            self
        }
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
