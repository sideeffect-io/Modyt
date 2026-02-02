import SwiftUI

struct MainTabView: View {
    @Bindable var store: AppStore

    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "square.grid.2x2") {
                NavigationStack {
                    DashboardView(store: store)
                }
            }

            Tab("Devices", systemImage: "square.stack.3d.up") {
                NavigationStack {
                    DevicesView(store: store)
                }
            }

            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    SettingsView(store: store)
                        .navigationTitle("Settings")
                }
            }
        }
    }
}
