import SwiftUI

struct RootTabView: View {
    @Environment(\.rootTabStoreFactory) private var rootTabStoreFactory
    @Environment(\.scenePhase) private var scenePhase
    
    let onDidDisconnect: @MainActor () -> Void
    
    var body: some View {
        WithStoreView(factory: rootTabStoreFactory.make) { store in
            content(for: store)
                .task {
                    store.send(.onStart)
                    store.send(.setAppActive(scenePhase == .active))
                }
                .onChange(of: scenePhase) { _, newPhase in
                    store.send(.setAppActive(newPhase == .active))
                }
                .onChange(of: store.state.didDisconnect) { _, didDisconnect in
                    guard didDisconnect else { return }
                    onDidDisconnect()
                }
        }
    }
    
    @ViewBuilder
    private func content(for store: RootTabStore) -> some View {
        let isForegroundReconnectInFlight = store.state.isForegroundReconnectInFlight
        let isInitialLoadBlocking = store.state.isInitialLoadBlocking
        let shouldBlockInteraction = isForegroundReconnectInFlight || isInitialLoadBlocking
        
        ZStack {
            tabContent()
                .blur(radius: shouldBlockInteraction ? 3 : 0)
                .allowsHitTesting(!shouldBlockInteraction)
            
            if isInitialLoadBlocking {
                InitialLoadOverlay(
                    errorMessage: store.state.initialLoad.errorMessage,
                    onRetry: { store.send(.retryInitialLoad) }
                )
                .transition(.opacity)
            } else if isForegroundReconnectInFlight {
                ForegroundReconnectOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shouldBlockInteraction)
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
            
            Tab("Scenes", systemImage: "sparkles.rectangle.stack") {
                NavigationStack {
                    TabBackgroundContainer {
                        ScenesView()
                            .hideChromeBackgroundForMobileTabs()
                    }
                }
                .clearNavigationContainerBackground()
            }

            Tab("Groups", systemImage: "square.grid.3x3.topleft.filled") {
                NavigationStack {
                    TabBackgroundContainer {
                        GroupsView()
                            .hideChromeBackgroundForMobileTabs()
                    }
                }
                .clearNavigationContainerBackground()
            }
            
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    TabBackgroundContainer {
                        SettingsView(onDidDisconnect: onDidDisconnect)
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

private struct ForegroundReconnectOverlay: View {
    var body: some View {
        ZStack {
            Color.black
                .opacity(0.08)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                Text("Negotiating secured access")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .glassCard(cornerRadius: 28, interactive: false)
            .padding()
        }
    }
}

private struct InitialLoadOverlay: View {
    let errorMessage: String?
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if let errorMessage {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("Gateway Sync Failed")
                        .font(.system(.title3, design: .rounded).weight(.semibold))

                    Text(errorMessage)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Retry", action: onRetry)
                        .buttonStyle(.borderedProminent)
                } else {
                    ProgressView()
                    Text("Loading devices, scenes, and groups")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 360)
            .glassCard(cornerRadius: 28, interactive: false)
            .padding()
        }
    }
}
