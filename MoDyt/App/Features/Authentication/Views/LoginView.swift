import SwiftUI
import DeltaDoreClient

struct LoginView: View {
    private enum Field: Hashable {
        case email
        case password
    }

    private struct LayoutMetrics {
        let isWide: Bool
        let outerPadding: CGFloat
        let sectionSpacing: CGFloat
        let columnSpacing: CGFloat
        let contentMaxWidth: CGFloat
        let heroWidth: CGFloat
        let heroHeight: CGFloat
        let formWidth: CGFloat
        let formPadding: CGFloat
        let illustrationPadding: CGFloat
        let siteListMaxHeight: CGFloat
        let minCanvasHeight: CGFloat

        init(containerSize: CGSize) {
            let width = max(containerSize.width, 320)
            let height = max(containerSize.height, 480)
            let isLandscape = width > height
            let wideEnoughForSplit = width >= 980 || (isLandscape && width >= 720)

            isWide = wideEnoughForSplit
            outerPadding = width >= 900 ? 32 : 20
            sectionSpacing = wideEnoughForSplit ? 28 : 22
            columnSpacing = wideEnoughForSplit ? 28 : 0
            contentMaxWidth = min(width - (outerPadding * 2), wideEnoughForSplit ? 1140 : 720)

            let resolvedFormWidth = min(wideEnoughForSplit ? 520 : contentMaxWidth, contentMaxWidth)
            formWidth = resolvedFormWidth
            heroWidth = wideEnoughForSplit
                ? max(320, contentMaxWidth - resolvedFormWidth - columnSpacing)
                : contentMaxWidth
            heroHeight = wideEnoughForSplit
                ? min(max(height * 0.60, 360), 460)
                : min(max(width * 0.64, 260), 360)
            formPadding = wideEnoughForSplit ? 28 : 24
            illustrationPadding = wideEnoughForSplit ? 28 : 24
            siteListMaxHeight = wideEnoughForSplit ? 308 : 276
            minCanvasHeight = height - 24
        }
    }

    @Bindable var store: AuthenticationStore
    let loginState: LoginState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @FocusState private var focusedField: Field?
    @State private var hasAnimatedIn = false

    var body: some View {
        GeometryReader { proxy in
            let metrics = LayoutMetrics(containerSize: proxy.size)

            ScrollView(.vertical, showsIndicators: false) {
                content(metrics: metrics)
                .frame(maxWidth: metrics.contentMaxWidth)
                .frame(minHeight: metrics.minCanvasHeight, alignment: .center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, metrics.outerPadding)
                .padding(.vertical, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sensoryFeedback(.selection, trigger: loginState.selectedSiteID)
        .sensoryFeedback(.warning, trigger: loginState.errorMessage)
        .onAppear {
            startAnimationsIfNeeded()
        }
    }

    @ViewBuilder
    private func content(metrics: LayoutMetrics) -> some View {
        if metrics.isWide {
            HStack(alignment: .center, spacing: metrics.columnSpacing) {
                heroPanel(metrics: metrics)
                    .frame(maxWidth: metrics.heroWidth, alignment: .leading)

                formPanel(metrics: metrics)
                    .frame(maxWidth: metrics.formWidth)
            }
        } else {
            VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                heroPanel(metrics: metrics)
                formPanel(metrics: metrics)
            }
        }
    }

    private func heroPanel(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                LoginBadge(
                    text: "Secure Tydom Access",
                    systemImage: "lock.shield.fill",
                    tone: .accent
                )

                Text("MoDyt")
                    .font(.system(metrics.isWide ? .largeTitle : .title, design: .rounded).weight(.bold))

                Text("Control your home with live Tydom data.")
                    .font(.system(metrics.isWide ? .title3 : .body, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("Sign in once, load the sites tied to your account, then connect to the right gateway without stretching the whole interface across the screen.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            illustrationPanel(metrics: metrics)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    heroCallout(
                        text: "Responsive layout",
                        systemImage: "rectangle.split.2x1.fill"
                    )
                    heroCallout(
                        text: "Site-aware login",
                        systemImage: "house.and.flag.fill"
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    heroCallout(
                        text: "Responsive layout",
                        systemImage: "rectangle.split.2x1.fill"
                    )
                    heroCallout(
                        text: "Site-aware login",
                        systemImage: "house.and.flag.fill"
                    )
                }
            }
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
                                    Color.white.opacity(colorScheme == .dark ? 0.04 : 0.22),
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
                color: AppColors.aurora.opacity(colorScheme == .dark ? 0.48 : 0.22),
                diameter: metrics.heroHeight * 0.78,
                xOffset: -metrics.heroWidth * 0.18,
                yOffset: -metrics.heroHeight * 0.22
            )

            ambientGlow(
                color: AppColors.ember.opacity(colorScheme == .dark ? 0.28 : 0.16),
                diameter: metrics.heroHeight * 0.62,
                xOffset: metrics.heroWidth * 0.24,
                yOffset: -metrics.heroHeight * 0.16
            )

            ambientGlow(
                color: AppColors.cloud.opacity(colorScheme == .dark ? 0.15 : 0.20),
                diameter: metrics.heroHeight * 0.92,
                xOffset: metrics.heroWidth * 0.12,
                yOffset: metrics.heroHeight * 0.26
            )

            Image("LoginIllustration")
                .resizable()
                .scaledToFit()
                .padding(metrics.illustrationPadding)
                .padding(.top, 24)
                .shadow(
                    color: AppColors.aurora.opacity(colorScheme == .dark ? 0.30 : 0.12),
                    radius: 28,
                    x: 0,
                    y: 12
                )

            VStack(alignment: .leading, spacing: 8) {
                LoginBadge(
                    text: "Live site selection",
                    systemImage: "sparkles",
                    tone: .neutral
                )
                Text("A calmer entry point for large screens and landscape.")
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.78 : 0.74))
                    .frame(maxWidth: 220, alignment: .leading)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: metrics.heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
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

    private func heroCallout(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.82 : 0.72))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.36))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.42),
                                lineWidth: 1
                            )
                    }
            }
    }

    private func formPanel(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in")
                        .font(.system(.title2, design: .rounded).weight(.bold))

                    Text("Use the same credentials and site selection flow you already have today, with a layout that stays balanced on iPhone and iPad.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                LoginBadge(
                    text: statusBadgeText,
                    systemImage: statusBadgeSymbol,
                    tone: loginState.canConnect ? .accent : .neutral
                )
            }

            credentialsSection
            sitesSection(metrics: metrics)

            if let error = loginState.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
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

            connectButton
        }
        .padding(metrics.formPadding)
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
        .animation(.spring(duration: 0.55, bounce: 0.12), value: loginState.errorMessage)
        .animation(.spring(duration: 0.55, bounce: 0.10), value: loginState.sites)
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Credentials")
                    .font(.system(.headline, design: .rounded).weight(.semibold))

                Text("Enter your Delta Dore account details to load the sites available to this login.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                CredentialField(
                    icon: "at",
                    isFocused: focusedField == .email,
                    isFilled: loginState.email.isEmpty == false
                ) {
                    TextField("Email", text: emailBinding)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .email)
                        .onSubmit {
                            focusedField = .password
                        }
                }

                CredentialField(
                    icon: "key.fill",
                    isFocused: focusedField == .password,
                    isFilled: loginState.password.isEmpty == false
                ) {
                    SecureField("Password", text: passwordBinding)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit {
                            loadSites()
                        }
                }

                Button {
                    loadSites()
                } label: {
                    HStack(spacing: 12) {
                        if loginState.isLoadingSites {
                            ProgressView()
                                .tint(colorScheme == .dark ? .white : AppColors.slate)
                        } else {
                            Image(systemName: loadSitesSymbolName)
                                .imageScale(.medium)
                                .contentTransition(.symbolEffect(.replace))
                                .symbolEffect(.bounce, value: loginState.canLoadSites)
                                .symbolEffect(.bounce, value: loginState.sites.count)
                        }

                        Text(loginState.isLoadingSites ? "Loading Sites..." : "Load Sites")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if loginState.sites.isEmpty == false {
                            Text(loginState.sites.count.formatted())
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentTransition(.numericText())
                                .background {
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.16))
                                }
                        }
                    }
                }
                .buttonStyle(SecondaryAuthenticationButtonStyle())
                .disabled(!loginState.canLoadSites || loginState.isLoadingSites)
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 26, interactive: false, tone: .inset)
    }

    private func sitesSection(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Site")
                        .font(.system(.headline, design: .rounded).weight(.semibold))

                    Text(loginState.sites.isEmpty
                         ? "Load your sites to continue."
                         : "Pick the site you want to use for this session.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(loginState.sites.count.formatted())
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.48))
                    }
            }

            if loginState.sites.isEmpty {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(AppColors.aurora.opacity(colorScheme == .dark ? 0.22 : 0.14))
                            .frame(width: 46, height: 46)

                        Image(systemName: "building.2.crop.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.82) : AppColors.slate)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("No site loaded yet")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                        Text("Use your credentials above to fetch the sites available for this account.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
                .glassCard(cornerRadius: 22, interactive: false, tone: .inset)
            } else {
                ScrollView(showsIndicators: loginState.sites.count > 3) {
                    LazyVStack(spacing: 12) {
                        ForEach(loginState.sites, id: \.id) { site in
                            siteRow(site)
                        }
                    }
                    .padding(2)
                }
                .frame(height: min(CGFloat(max(loginState.sites.count, 1)) * 82, metrics.siteListMaxHeight))
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 26, interactive: false, tone: .inset)
    }

    private func siteRow(_ site: DeltaDoreClient.Site) -> some View {
        let isSelected = loginState.selectedSiteID == site.id

        return Button {
            store.send(.siteSelected(site.id))
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            isSelected
                                ? AppColors.aurora.opacity(colorScheme == .dark ? 0.24 : 0.18)
                                : Color.white.opacity(colorScheme == .dark ? 0.06 : 0.46)
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "house.fill")
                        .imageScale(.medium)
                        .foregroundStyle(
                            isSelected
                                ? AnyShapeStyle(AppColors.ember)
                                : AnyShapeStyle(.secondary)
                        )
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: isSelected)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(site.name)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(gatewayLabel(for: site))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text(isSelected ? "Selected" : site.gateways.count.formatted())
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule(style: .continuous)
                            .fill(
                                isSelected
                                    ? AppColors.ember.opacity(colorScheme == .dark ? 0.18 : 0.20)
                                    : Color.white.opacity(colorScheme == .dark ? 0.06 : 0.44)
                            )
                    }
                    .foregroundStyle(isSelected ? AppColors.ember : .secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .scaleEffect(isSelected ? 1.01 : 1)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(
                                colors: [
                                    AppColors.aurora.opacity(colorScheme == .dark ? 0.16 : 0.18),
                                    AppColors.ember.opacity(colorScheme == .dark ? 0.08 : 0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.03 : 0.36),
                                    Color.white.opacity(colorScheme == .dark ? 0.01 : 0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? AppColors.aurora.opacity(colorScheme == .dark ? 0.42 : 0.28)
                                    : Color.white.opacity(colorScheme == .dark ? 0.06 : 0.36),
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.20), value: isSelected)
    }

    private var connectButton: some View {
        Button {
            store.send(.connectTapped)
        } label: {
            HStack(spacing: 12) {
                if loginState.isConnecting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: loginState.canConnect ? "arrow.right.circle.fill" : "arrow.right.circle")
                        .imageScale(.large)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: loginState.canConnect)
                }

                Text(loginState.isConnecting ? "Connecting..." : "Connect")
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let selectedSiteName {
                    Text(selectedSiteName)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.18))
                        }
                }
            }
        }
        .buttonStyle(PrimaryAuthenticationButtonStyle())
        .disabled(!loginState.canConnect)
    }

    private var emailBinding: Binding<String> {
        Binding(
            get: { loginState.email },
            set: { store.send(.loginEmailChanged($0)) }
        )
    }

    private var passwordBinding: Binding<String> {
        Binding(
            get: { loginState.password },
            set: { store.send(.loginPasswordChanged($0)) }
        )
    }

    private var selectedSiteName: String? {
        loginState.sites.first(where: { $0.id == loginState.selectedSiteID })?.name
    }

    private var statusBadgeText: String {
        if loginState.isConnecting {
            return "Connecting"
        }
        if loginState.canConnect {
            return "Ready"
        }
        if loginState.sites.isEmpty == false {
            return "Pick site"
        }
        return "Load sites"
    }

    private var statusBadgeSymbol: String {
        if loginState.isConnecting {
            return "bolt.circle.fill"
        }
        if loginState.canConnect {
            return "checkmark.circle.fill"
        }
        if loginState.sites.isEmpty == false {
            return "house.badge"
        }
        return "arrow.down.circle.fill"
    }

    private var loadSitesSymbolName: String {
        if loginState.sites.isEmpty {
            return "sparkle.magnifyingglass"
        }
        return "arrow.clockwise.circle.fill"
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
                    AppColors.sunrise.opacity(0.52)
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

    private func gatewayLabel(for site: DeltaDoreClient.Site) -> String {
        "\(site.gateways.count) \(site.gateways.count == 1 ? "gateway" : "gateways")"
    }

    private func loadSites() {
        guard loginState.canLoadSites, !loginState.isLoadingSites else { return }
        store.send(.loadSitesTapped)
    }

    private func startAnimationsIfNeeded() {
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true
    }
}

private enum LoginBadgeTone {
    case neutral
    case accent
}

private struct LoginBadge: View {
    let text: String
    let systemImage: String
    let tone: LoginBadgeTone

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

private struct CredentialField<Content: View>: View {
    let icon: String
    let isFocused: Bool
    let isFilled: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 20)
                .symbolEffect(.bounce, value: isFocused)
                .scaleEffect(isFocused ? 1.08 : 1)

            content()
                .textFieldStyle(.plain)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(backgroundFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(borderStyle, lineWidth: isFocused ? 1.5 : 1)
                }
                .shadow(
                    color: isFocused
                        ? AppColors.aurora.opacity(colorScheme == .dark ? 0.18 : 0.10)
                        : .clear,
                    radius: 14,
                    x: 0,
                    y: 8
                )
        }
        .scaleEffect(isFocused ? 1.01 : 1)
        .animation(.snappy(duration: 0.20), value: isFocused)
        .animation(.snappy(duration: 0.20), value: isFilled)
    }

    private var iconColor: AnyShapeStyle {
        if isFocused {
            return AnyShapeStyle(AppColors.aurora)
        }

        if isFilled {
            return AnyShapeStyle(colorScheme == .dark ? Color.white.opacity(0.82) : AppColors.slate)
        }

        return AnyShapeStyle(colorScheme == .dark ? Color.white.opacity(0.70) : AppColors.slate.opacity(0.80))
    }

    private var backgroundFill: some ShapeStyle {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(isFocused ? 0.10 : 0.06),
                    Color.white.opacity(isFocused ? 0.06 : 0.03)
                ]
                : [
                    Color.white.opacity(isFocused ? 0.72 : 0.54),
                    AppColors.cloud.opacity(isFocused ? 0.26 : 0.12)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderStyle: AnyShapeStyle {
        if isFocused {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        AppColors.aurora.opacity(colorScheme == .dark ? 0.72 : 0.56),
                        AppColors.ember.opacity(colorScheme == .dark ? 0.48 : 0.34)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.42))
    }
}

private struct PrimaryAuthenticationButtonStyle: ButtonStyle {
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

private struct SecondaryAuthenticationButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background {
                Capsule(style: .continuous)
                    .fill(backgroundFill)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(colorScheme == .dark ? 0.10 : 0.36),
                                lineWidth: 1
                            )
                    }
            }
            .opacity(isEnabled ? 1 : 0.62)
            .scaleEffect(configuration.isPressed ? 0.988 : (isEnabled ? 1 : 0.994))
            .shadow(
                color: isEnabled
                    ? AppColors.aurora.opacity(colorScheme == .dark ? 0.10 : 0.06)
                    : .clear,
                radius: 12,
                x: 0,
                y: 8
            )
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
            .animation(.snappy(duration: 0.22), value: isEnabled)
    }

    private var backgroundFill: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(isEnabled ? 0.10 : 0.04),
                    Color.white.opacity(isEnabled ? 0.06 : 0.02)
                ]
                : [
                    Color.white.opacity(isEnabled ? 0.70 : 0.34),
                    AppColors.cloud.opacity(isEnabled ? 0.32 : 0.18)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
