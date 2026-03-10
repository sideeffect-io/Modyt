import SwiftUI

struct SettingsView: View {
    private struct LayoutMetrics {
        let isWide: Bool
        let outerPadding: CGFloat
        let sectionSpacing: CGFloat
        let columnSpacing: CGFloat
        let contentMaxWidth: CGFloat
        let heroWidth: CGFloat
        let panelWidth: CGFloat
        let heroHeight: CGFloat
        let panelPadding: CGFloat
        let illustrationPadding: CGFloat
        let minCanvasHeight: CGFloat

        init(containerSize: CGSize) {
            let width = max(containerSize.width, 320)
            let height = max(containerSize.height, 480)
            let isLandscape = width > height
            let wideEnoughForSplit = width >= 920 || (isLandscape && width >= 720)

            isWide = wideEnoughForSplit
            outerPadding = width >= 900 ? 32 : 20
            sectionSpacing = wideEnoughForSplit ? 28 : 22
            columnSpacing = wideEnoughForSplit ? 28 : 0
            contentMaxWidth = min(
                width - (outerPadding * 2),
                wideEnoughForSplit ? 1120 : 720
            )

            let resolvedPanelWidth = min(
                wideEnoughForSplit ? 470 : contentMaxWidth,
                contentMaxWidth
            )

            panelWidth = resolvedPanelWidth
            heroWidth = wideEnoughForSplit
                ? max(320, contentMaxWidth - resolvedPanelWidth - columnSpacing)
                : contentMaxWidth
            heroHeight = wideEnoughForSplit
                ? min(max(height * 0.54, 340), 430)
                : min(max(width * 0.54, 220), 320)
            panelPadding = wideEnoughForSplit ? 30 : 24
            illustrationPadding = wideEnoughForSplit ? 30 : 24
            minCanvasHeight = height - 24
        }
    }

    @Environment(\.settingsStoreDependencies) private var settingsStoreDependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let onDidDisconnect: @MainActor () -> Void

    @State private var hasAnimatedIn = false

    var body: some View {
        WithStoreView(
            store: SettingsStore(dependencies: settingsStoreDependencies),
        ) { store in
            GeometryReader { proxy in
                let metrics = LayoutMetrics(containerSize: proxy.size)

                ScrollView(.vertical, showsIndicators: false) {
                    content(store: store, metrics: metrics)
                        .frame(maxWidth: metrics.contentMaxWidth)
                        .frame(
                            minHeight: metrics.minCanvasHeight,
                            alignment: metrics.isWide ? .center : .top
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, metrics.outerPadding)
                        .padding(.vertical, 24)
                }
                .sensoryFeedback(.success, trigger: store.state.didDisconnect)
                .sensoryFeedback(.warning, trigger: store.state.errorMessage)
            }
            .onAppear {
                startAnimationsIfNeeded()
            }
            .onChange(of: store.state.didDisconnect) { _, didDisconnect in
                guard didDisconnect else { return }
                onDidDisconnect()
            }
        }
    }

    @ViewBuilder
    private func content(store: SettingsStore, metrics: LayoutMetrics) -> some View {
        if metrics.isWide {
            HStack(alignment: .bottom, spacing: metrics.columnSpacing) {
                heroPanel(metrics: metrics)
                    .frame(maxWidth: metrics.heroWidth, alignment: .leading)

                connectionPanel(store: store, metrics: metrics)
                    .frame(maxWidth: metrics.panelWidth)
            }
        } else {
            VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                heroPanel(metrics: metrics)
                connectionPanel(store: store, metrics: metrics)
            }
        }
    }

    private func heroPanel(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsBadge(
                text: "Account Session",
                systemImage: "person.crop.circle.badge.checkmark",
                tone: .accent
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("A calmer settings screen for every orientation.")
                    .font(.system(metrics.isWide ? .largeTitle : .title2, design: .rounded).weight(.bold))

                Text("Disconnect only when you need a fresh sign-in or want to switch accounts. On iPad and landscape, the screen now stays compact instead of stretching the action edge to edge.")
                    .font(.system(metrics.isWide ? .title3 : .body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            illustrationPanel(metrics: metrics)
        }
        .opacity(hasAnimatedIn ? 1 : 0)
        .offset(
            x: hasAnimatedIn ? 0 : (metrics.isWide ? -32 : 0),
            y: hasAnimatedIn ? 0 : 18
        )
        .animation(
            reduceMotion ? nil : .spring(duration: 0.85, bounce: 0.16),
            value: hasAnimatedIn
        )
    }

    private func illustrationPanel(metrics: LayoutMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(heroPanelGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.04 : 0.20),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(colorScheme == .dark ? 0.10 : 0.42),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08),
                    radius: colorScheme == .dark ? 28 : 18,
                    x: 0,
                    y: 18
                )

            ambientGlow(
                color: AppColors.aurora.opacity(colorScheme == .dark ? 0.48 : 0.20),
                diameter: metrics.heroHeight * 0.76,
                xOffset: -metrics.heroWidth * 0.16,
                yOffset: -metrics.heroHeight * 0.18
            )

            ambientGlow(
                color: AppColors.ember.opacity(colorScheme == .dark ? 0.24 : 0.14),
                diameter: metrics.heroHeight * 0.56,
                xOffset: metrics.heroWidth * 0.22,
                yOffset: -metrics.heroHeight * 0.16
            )

            ambientGlow(
                color: AppColors.cloud.opacity(colorScheme == .dark ? 0.14 : 0.16),
                diameter: metrics.heroHeight * 0.88,
                xOffset: metrics.heroWidth * 0.08,
                yOffset: metrics.heroHeight * 0.20
            )

            GeometryReader { proxy in
                Image("SettingsIllustration")
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [
                                    Color.black.opacity(0.16),
                                    Color.clear,
                                    Color.black.opacity(0.24)
                                ]
                                : [
                                    Color.white.opacity(0.10),
                                    Color.clear,
                                    Color.black.opacity(0.08)
                                ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .shadow(
                        color: AppColors.aurora.opacity(colorScheme == .dark ? 0.24 : 0.10),
                        radius: 24,
                        x: 0,
                        y: 10
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsBadge(
                    text: "Session control",
                    systemImage: "switch.2",
                    tone: .neutral
                )
                Text("Compact, readable, and easy to reset when you need a new sign-in.")
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.78 : 0.74))
                    .frame(maxWidth: 230, alignment: .leading)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: metrics.heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private func connectionPanel(
        store: SettingsStore,
        metrics: LayoutMetrics
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection")
                        .font(.system(.title2, design: .rounded).weight(.bold))

                    Text("Disconnect to switch account or re-run setup. You can sign back in right away and reconnect to the same site or choose another one.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                SettingsBadge(
                    text: connectionStatusText(for: store.state),
                    systemImage: connectionStatusSymbol(for: store.state),
                    tone: store.state.isDisconnecting ? .neutral : .accent
                )
            }

            VStack(spacing: 14) {
                SettingsInfoCard(
                    title: "What happens next",
                    message: "The active gateway session closes on this device, then the sign-in flow becomes available immediately.",
                    systemImage: "rectangle.portrait.and.arrow.right"
                )

                SettingsInfoCard(
                    title: "When to use this",
                    message: "Switch accounts, refresh setup, or clear the current session before handing the device to someone else.",
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
                )
            }

            if let errorMessage = store.state.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.red.opacity(colorScheme == .dark ? 0.14 : 0.10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.red.opacity(0.20), lineWidth: 1)
                            }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Button {
                store.send(.disconnectTapped)
            } label: {
                HStack(spacing: 12) {
                    if store.state.isDisconnecting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "power.circle.fill")
                            .imageScale(.large)
                    }

                    Text(store.state.isDisconnecting ? "Disconnecting..." : "Disconnect")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(store.state.isDisconnecting ? "Working" : "One tap")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.18))
                        }
                }
            }
            .buttonStyle(SettingsPrimaryActionButtonStyle())
            .disabled(store.state.isDisconnecting)
        }
        .padding(metrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(formPanelGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(colorScheme == .dark ? 0.10 : 0.36),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08),
                    radius: colorScheme == .dark ? 24 : 16,
                    x: 0,
                    y: 16
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .opacity(hasAnimatedIn ? 1 : 0)
        .offset(
            x: hasAnimatedIn ? 0 : (metrics.isWide ? 32 : 0),
            y: hasAnimatedIn ? 0 : 20
        )
        .animation(
            reduceMotion ? nil : .spring(duration: 0.90, bounce: 0.12),
            value: hasAnimatedIn
        )
        .animation(.spring(duration: 0.55, bounce: 0.12), value: store.state.errorMessage)
        .animation(.spring(duration: 0.55, bounce: 0.10), value: store.state.isDisconnecting)
    }

    private func ambientGlow(
        color: Color,
        diameter: CGFloat,
        xOffset: CGFloat,
        yOffset: CGFloat
    ) -> some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .blur(radius: diameter * 0.18)
            .offset(x: xOffset, y: yOffset)
    }

    private func connectionStatusText(for state: SettingsState) -> String {
        if state.isDisconnecting {
            return "Disconnecting"
        }
        if state.errorMessage != nil {
            return "Retry"
        }
        return "Connected"
    }

    private func connectionStatusSymbol(for state: SettingsState) -> String {
        if state.isDisconnecting {
            return "bolt.slash.circle.fill"
        }
        if state.errorMessage != nil {
            return "exclamationmark.circle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var heroPanelGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.08, green: 0.13, blue: 0.19),
                    Color(red: 0.07, green: 0.10, blue: 0.16),
                    Color(red: 0.10, green: 0.12, blue: 0.18)
                ]
                : [
                    Color.white.opacity(0.88),
                    AppColors.cloud.opacity(0.80),
                    AppColors.sunrise.opacity(0.48)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var formPanelGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.06, green: 0.11, blue: 0.16).opacity(0.92),
                    Color(red: 0.08, green: 0.13, blue: 0.19).opacity(0.94)
                ]
                : [
                    Color.white.opacity(0.74),
                    Color.white.opacity(0.60),
                    AppColors.cloud.opacity(0.38)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func startAnimationsIfNeeded() {
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true
    }
}

private enum SettingsBadgeTone {
    case neutral
    case accent
}

private struct SettingsBadge: View {
    let text: String
    let systemImage: String
    let tone: SettingsBadgeTone

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                Capsule(style: .continuous)
                    .fill(backgroundGradient)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    }
            }
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral:
            return colorScheme == .dark ? Color.white.opacity(0.84) : AppColors.slate
        case .accent:
            return colorScheme == .dark ? Color.white : AppColors.slate
        }
    }

    private var backgroundGradient: LinearGradient {
        switch tone {
        case .neutral:
            return LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.10 : 0.58),
                    Color.white.opacity(colorScheme == .dark ? 0.05 : 0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .accent:
            return LinearGradient(
                colors: [
                    AppColors.aurora.opacity(colorScheme == .dark ? 0.42 : 0.30),
                    AppColors.ember.opacity(colorScheme == .dark ? 0.30 : 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        switch tone {
        case .neutral:
            return Color.white.opacity(colorScheme == .dark ? 0.08 : 0.42)
        case .accent:
            return Color.white.opacity(colorScheme == .dark ? 0.12 : 0.46)
        }
    }
}

private struct SettingsInfoCard: View {
    let title: String
    let message: String
    let systemImage: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppColors.aurora.opacity(colorScheme == .dark ? 0.24 : 0.14))
                    .frame(width: 42, height: 42)

                Image(systemName: systemImage)
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.82) : AppColors.slate)
                    .imageScale(.medium)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text(message)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard(cornerRadius: 22, interactive: false, tone: .inset)
    }
}

private struct SettingsPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background {
                Capsule(style: .continuous)
                    .fill(backgroundGradient)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(isEnabled ? 0.22 : 0.08),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: AppColors.ember.opacity(isEnabled ? 0.22 : 0.0),
                        radius: 18,
                        x: 0,
                        y: 10
                    )
            }
            .opacity(isEnabled ? 1 : 0.58)
            .scaleEffect(configuration.isPressed ? 0.985 : (isEnabled ? 1 : 0.992))
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
            .animation(.snappy(duration: 0.22), value: isEnabled)
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: isEnabled
                ? [AppColors.aurora, AppColors.ember]
                : [Color.secondary.opacity(0.32), Color.secondary.opacity(0.18)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
