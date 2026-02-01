import SwiftUI
import MoDytCore

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var store: AppStore

    var body: some View {
        Group {
            switch store.state.authStatus {
            case .connected:
                MainShellView(store: store)
            case .selectingSite:
                AuthFlowView(store: store)
            case .needsCredentials, .connecting, .idle, .error:
                AuthFlowView(store: store)
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            store.send(.setAppActive(newValue == .active))
        }
    }
}

private struct MainShellView: View {
    @Bindable var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: 20) {
                shellContent
            }
        } else {
            shellContent
        }
    }

    private var horizontalIsRegular: Bool {
        horizontalSizeClass == .regular
    }

    @ViewBuilder
    private var shellContent: some View {
        #if os(macOS)
        NavigationSplitView {
            SidebarView(store: store)
        } content: {
            ContentSwitcherView(store: store)
        } detail: {
            DetailPlaceholderView()
        }
        #else
        if horizontalIsRegular {
            NavigationSplitView {
                SidebarView(store: store)
            } content: {
                ContentSwitcherView(store: store)
            } detail: {
                DetailPlaceholderView()
            }
        } else {
            TabView {
                Tab("Dashboard", systemImage: "square.grid.2x2") {
                    NavigationStack {
                        DashboardView(store: store)
                    }
                }
                Tab("Devices", systemImage: "list.bullet") {
                    NavigationStack {
                        DevicesListView(store: store)
                    }
                }
                Tab("Settings", systemImage: "gear") {
                    NavigationStack {
                        SettingsView(store: store)
                    }
                }
            }
        }
        #endif
    }
}

private struct SidebarView: View {
    @Bindable var store: AppStore

    var body: some View {
        List {
            Section("Modes") {
                Button {
                    store.send(.appModeChanged(.dashboard))
                } label: {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.plain)

                Button {
                    store.send(.appModeChanged(.complete))
                } label: {
                    Label("Devices", systemImage: "list.bullet")
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("MoDyt")
    }
}

private struct ContentSwitcherView: View {
    @Bindable var store: AppStore

    var body: some View {
        switch store.state.mode {
        case .dashboard:
            DashboardView(store: store)
        case .complete:
            DevicesListView(store: store)
        }
    }
}

private struct DetailPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "house.lodge")
                .font(.system(size: 32, weight: .semibold))
            Text("Select a device")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(glassBackground)
    }

    private var glassBackground: some ShapeStyle {
        if #available(iOS 26, macOS 26, *) {
            return AnyShapeStyle(.regularMaterial)
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

private struct SettingsView: View {
    @Bindable var store: AppStore

    var body: some View {
        List {
            Button("Disconnect") {
                store.send(.disconnectRequested)
            }
            .foregroundStyle(.red)
        }
        .navigationTitle("Settings")
    }
}
