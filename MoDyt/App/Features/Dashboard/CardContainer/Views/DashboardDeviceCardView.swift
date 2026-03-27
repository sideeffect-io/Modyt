import SwiftUI

struct DashboardDeviceCardView: View {
    @Environment(\.dashboardDeviceCardStoreFactory) private var dashboardDeviceCardStoreFactory

    let favorite: FavoriteItem
    let isEditing: Bool
    let editAnimationVersion: Int
    let onRequestEditMode: () -> Void

    @ScaledMetric(relativeTo: .body) private var dashboardCardMinHeight: CGFloat = 194
    @ScaledMetric(relativeTo: .title3) private var cardIconSize: CGFloat = 22
    @ScaledMetric(relativeTo: .title3) private var cardIconFrame: CGFloat = 30
    @ScaledMetric(relativeTo: .title3) private var cardHeaderSpacing: CGFloat = 6
    @ScaledMetric(relativeTo: .title3) private var favoriteButtonInset: CGFloat = 10
    @ScaledMetric(relativeTo: .title3) private var favoriteButtonClearance: CGFloat = 50

    @State private var isWiggling = false

    private let cardCornerRadius: CGFloat = 22

    var body: some View {
        WithStoreView(
            store: dashboardDeviceCardStoreFactory.make(favoriteType: favorite.type),
        ) { store in
            cardContent(
                for: favorite,
                onFavoriteTapped: { store.send(.favoriteTapped) }
            )
        }
    }

    @ViewBuilder
    private func cardContent(
        for favorite: FavoriteItem,
        onFavoriteTapped: @escaping () -> Void
    ) -> some View {
        if favorite.isScene {
            sceneCardContent(for: favorite, onFavoriteTapped: onFavoriteTapped)
        } else {
            deviceCardContent(for: favorite, onFavoriteTapped: onFavoriteTapped)
        }
    }

    private func sceneCardContent(
        for favorite: FavoriteItem,
        onFavoriteTapped: @escaping () -> Void
    ) -> some View {
        cardShell(for: favorite, onFavoriteTapped: onFavoriteTapped) {
            Spacer(minLength: 0)

            SceneExecutionView(uniqueId: favorite.sceneExecutionUniqueId)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func deviceCardContent(
        for favorite: FavoriteItem,
        onFavoriteTapped: @escaping () -> Void
    ) -> some View {
        cardShell(for: favorite, onFavoriteTapped: onFavoriteTapped) {
            if let passiveLabel = passiveBodyLabel(for: favorite) {
                Text(passiveLabel)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            controlContent(for: favorite)
        }
    }

    private func cardShell<Content: View>(
        for favorite: FavoriteItem,
        onFavoriteTapped: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(for: favorite)
            content()
                .allowsHitTesting(!isEditing)
                .opacity(isEditing ? 0.72 : 1)
        }
        .padding(16)
        .frame(minHeight: dashboardCardMinHeight, alignment: .top)
        .glassCard(cornerRadius: cardCornerRadius)
        .overlay {
            if isEditing {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(.black.opacity(0.05))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isEditing {
                favoriteButton(for: favorite, action: onFavoriteTapped)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .rotationEffect(.degrees(isEditing ? (isWiggling ? wiggleAngle : -wiggleAngle) : 0))
        .offset(y: isEditing ? (isWiggling ? -0.6 : 0.6) : 0)
        .simultaneousGesture(editModeGesture)
        .onAppear(perform: updateWiggleState)
        .onChange(of: isEditing) {
            updateWiggleState()
        }
        .onChange(of: editAnimationVersion) {
            updateWiggleState()
        }
        .onChange(of: favorite.id) {
            updateWiggleState()
        }
    }

    private func cardHeader(for favorite: FavoriteItem) -> some View {
        compactHeader(for: favorite)
            .padding(.trailing, isEditing ? favoriteButtonClearance : 0)
    }

    private func compactHeader(for favorite: FavoriteItem) -> some View {
        HStack(alignment: .center, spacing: cardHeaderSpacing) {
            headerIcon(for: favorite)

            Text(favorite.name)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headerIcon(for favorite: FavoriteItem) -> some View {
        Image(systemName: iconSystemName(for: favorite))
            .font(.system(size: cardIconSize, weight: .semibold))
            .frame(width: cardIconFrame, height: cardIconFrame, alignment: .leading)
    }

    private func favoriteButton(
        for favorite: FavoriteItem,
        action: @escaping () -> Void
    ) -> some View {
        FavoriteOrbButton(
            isFavorite: true,
            size: 32,
            accessibilityContext: favorite.name,
            action: action
        )
        .padding(favoriteButtonInset)
    }

    private var editModeGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.55, maximumDistance: 12)
            .onEnded { _ in
                guard !isEditing else { return }
                onRequestEditMode()
            }
    }

    private var wiggleAngle: Double {
        favorite.id.hashValue.isMultiple(of: 2) ? 1.15 : -1.15
    }

    private func updateWiggleState() {
        guard isEditing else {
            withAnimation(.easeOut(duration: 0.14)) {
                isWiggling = false
            }
            return
        }

        withAnimation(
            .easeInOut(duration: 0.16)
                .repeatForever(autoreverses: true)
                .delay(Double(abs(favorite.id.hashValue % 7)) * 0.02)
        ) {
            isWiggling = true
        }
    }

    private func iconSystemName(for favorite: FavoriteItem) -> String {
        if favorite.isScene {
            return sceneSymbolName(picto: nil, type: nil)
        }

        switch favorite.controlKind {
        case .heatPump:
            return "heat.waves"
        case .thermostat:
            return "thermometer"
        case .temperature:
            return "thermometer.medium"
        case .sunlight:
            return "sun.max.fill"
        case .smoke:
            return smokeSymbolName()
        default:
            return favorite.group.symbolName
        }
    }

    @ViewBuilder
    private func controlContent(for favorite: FavoriteItem) -> some View {
        if supportsActiveControls(for: favorite) {
            switch favorite.controlKind {
            case .shutter:
                switch DashboardShutterRoute(favorite: favorite) {
                case .unavailable:
                    Text("Shutters unavailable")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                case .single(let deviceId):
                    SingleShutterView(
                        deviceId: deviceId
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                case .group(let deviceIds):
                    GroupShutterView(
                        deviceIds: deviceIds
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .light:
                switch DashboardLightRoute(favorite: favorite) {
                case .unavailable:
                    Text("Lights unavailable")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                case .single(let deviceId):
                    SingleLightView(deviceId: deviceId)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                case .group(let deviceIds):
                    GroupLightView(deviceIds: deviceIds)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .temperature:
                if let identifier = favorite.controlDeviceIdentifier {
                    TemperatureView(identifier: identifier)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .thermostat:
                if let identifier = favorite.controlDeviceIdentifier {
                    ThermostatView(identifier: identifier)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .heatPump:
                if let identifier = favorite.controlDeviceIdentifier {
                    HeatPumpView(identifier: identifier)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .sunlight:
                if let identifier = favorite.controlDeviceIdentifier {
                    SunlightView(identifier: identifier)
                }
            case .energyConsumption:
                if let identifier = favorite.controlDeviceIdentifier {
                    EnergyConsumptionView(identifier: identifier)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .smoke:
                if let identifier = favorite.controlDeviceIdentifier {
                    SmokeView(identifier: identifier)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            default:
                EmptyView()
            }
        } else {
            EmptyView()
        }
    }

    private func supportsActiveControls(for favorite: FavoriteItem) -> Bool {
        if favorite.isGroup {
            return favorite.controlKind == .light || favorite.controlKind == .shutter
        }

        switch favorite.controlKind {
        case .shutter, .light, .temperature, .thermostat, .heatPump, .sunlight, .energyConsumption, .smoke:
            return true
        default:
            return false
        }
    }

    private func passiveBodyLabel(for favorite: FavoriteItem) -> String? {
        guard !supportsActiveControls(for: favorite) else { return nil }
        if favorite.isGroup {
            return favorite.usage.rawValue.capitalized
        }
        return favorite.group.title
    }

    private func smokeSymbolName() -> String {
        let preferredSymbols = [
            "fire.extinguisher.fill",
            "sensor.fill",
            "flame.fill"
        ]

        for symbol in preferredSymbols where UIImage(systemName: symbol) != nil {
            return symbol
        }

        return "exclamationmark.triangle.fill"
    }
}
