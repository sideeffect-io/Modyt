import SwiftUI

enum MainPresentationState: Equatable {
    case none
    case progress(String)
    case gatewayHandlingError
    case reconnectionError
}

func mainPresentationState(for featureState: MainFeatureState) -> MainPresentationState {
    switch featureState {
    case .featureIsIdle,
         .featureIsStarted,
         .userIsDisconnected:
        return .none

    case .gatewayHandlingIsStarting:
        return .progress("Loading gateway data")

    case .disconnectionIsInProgress:
        return .progress("Disconnecting")

    case .reconnectionIsInProgress:
        return .progress("Reconnecting")

    case .gatewayHandlingIsInError:
        return .gatewayHandlingError

    case .reconnectionIsInError:
        return .reconnectionError
    }
}

func shouldBlockMainInteraction(for featureState: MainFeatureState) -> Bool {
    switch mainPresentationState(for: featureState) {
    case .none:
        return false
    case .progress, .gatewayHandlingError, .reconnectionError:
        return true
    }
}

func mainEvent(for scenePhase: ScenePhase) -> MainEvent {
    if scenePhase == .active {
        return .appActiveWasReceived
    }
    return .appInactiveWasReceived
}

func shouldNotifyParentOnMainFeatureStateChange(
    previous: MainFeatureState,
    current: MainFeatureState
) -> Bool {
    previous != .userIsDisconnected && current == .userIsDisconnected
}

struct MainView: View {
    @Environment(\.mainStoreFactory) private var mainStoreFactory
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: MainTab = .dashboard

    let onDisconnected: @MainActor () -> Void

    var body: some View {
        WithStoreView(factory: mainStoreFactory.make) { store in
            content(for: store)
                .task {
                    store.send(.startingGatewayHandlingWasRequested)
                    store.send(mainEvent(for: scenePhase))
                }
                .onChange(of: scenePhase) { _, newPhase in
                    store.send(mainEvent(for: newPhase))
                }
                .onChange(of: store.state.featureState) { oldFeatureState, featureState in
                    if shouldNotifyParentOnMainFeatureStateChange(
                        previous: oldFeatureState,
                        current: featureState
                    ) {
                        onDisconnected()
                    }
                }
        }
    }

    @ViewBuilder
    private func content(for store: MainStore) -> some View {
        let featureState = store.state.featureState
        let presentation = mainPresentationState(for: featureState)
        let shouldBlockInteraction = shouldBlockMainInteraction(for: featureState)

        ZStack {
            tabContent()
                .blur(radius: shouldBlockInteraction ? 3 : 0)
                .allowsHitTesting(!shouldBlockInteraction)

            switch presentation {
            case .none:
                EmptyView()

            case .progress(let message):
                MainProgressOverlay(message: message)
                    .transition(.opacity)

            case .gatewayHandlingError:
                MainErrorPopup(
                    title: "Gateway Loading Failed",
                    message: "Unable to load data from the gateway.",
                    onRetry: { store.send(.startingGatewayHandlingWasRequested) },
                    onDisconnect: { store.send(.disconnectionWasRequested) }
                )
                .transition(.opacity)

            case .reconnectionError:
                MainErrorPopup(
                    title: "Reconnection Failed",
                    message: "The app could not reconnect to your gateway.",
                    onRetry: { store.send(.reconnectionWasRequested) },
                    onDisconnect: { store.send(.disconnectionWasRequested) }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: featureState)
    }

    @ViewBuilder
    private func tabContent() -> some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "square.grid.2x2", value: MainTab.dashboard) {
                NavigationStack {
                    MainTabBackgroundContainer {
                        DashboardView()
                            .hideChromeBackgroundForMainTabs()
                    }
                }
                .clearMainNavigationContainerBackground()
            }

            Tab("Devices", systemImage: "square.stack.3d.up", value: MainTab.devices) {
                NavigationStack {
                    MainTabBackgroundContainer {
                        DevicesView()
                            .hideChromeBackgroundForMainTabs()
                    }
                }
                .clearMainNavigationContainerBackground()
            }

            Tab("Groups", systemImage: "square.grid.3x3.topleft.filled", value: MainTab.groups) {
                NavigationStack {
                    MainTabBackgroundContainer {
                        GroupsView()
                            .hideChromeBackgroundForMainTabs()
                    }
                }
                .clearMainNavigationContainerBackground()
            }

            Tab("Scenes", systemImage: "sparkles.rectangle.stack", value: MainTab.scenes) {
                NavigationStack {
                    MainTabBackgroundContainer {
                        ScenesView()
                            .hideChromeBackgroundForMainTabs()
                    }
                }
                .clearMainNavigationContainerBackground()
            }

            Tab("Settings", systemImage: "gearshape", value: MainTab.settings) {
                NavigationStack {
                    MainTabBackgroundContainer {
                        SettingsView(onDidDisconnect: onDisconnected)
                            .navigationTitle("Settings")
                            .hideChromeBackgroundForMainTabs()
                    }
                }
                .clearMainNavigationContainerBackground()
            }
        }
    }
}

private enum MainTab: Hashable {
    case dashboard
    case devices
    case groups
    case scenes
    case settings
}

private extension View {
    @ViewBuilder
    func hideChromeBackgroundForMainTabs() -> some View {
#if os(iOS)
        self
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .tabBar)
#else
        self
#endif
    }

    @ViewBuilder
    func clearMainNavigationContainerBackground() -> some View {
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

private struct MainTabBackgroundContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            AppBackgroundView()
            content
        }
    }
}

private struct MainProgressOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                Text(message)
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .glassCard(cornerRadius: 28, interactive: false)
            .padding()
        }
    }
}

private struct MainErrorPopup: View {
    let title: String
    let message: String
    let onRetry: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.semibold))

                Text(message)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.borderedProminent)

                    Button("Disconnect", action: onDisconnect)
                        .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .glassCard(cornerRadius: 28, interactive: false)
            .padding()
        }
    }
}
