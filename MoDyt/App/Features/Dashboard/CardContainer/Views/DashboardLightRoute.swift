import Foundation

enum DashboardLightRoute: Equatable {
    case unavailable
    case single(DeviceIdentifier)
    case group([DeviceIdentifier])

    init(favorite: FavoriteItem) {
        guard favorite.controlKind == .light else {
            self = .unavailable
            return
        }

        if favorite.isGroup {
            let identifiers = favorite.lightIdentifiers.uniquePreservingOrder()
            self = identifiers.isEmpty ? .unavailable : .group(identifiers)
            return
        }

        if let deviceId = favorite.controlDeviceIdentifier {
            self = .single(deviceId)
            return
        }

        if let deviceId = favorite.lightIdentifiers.uniquePreservingOrder().first {
            self = .single(deviceId)
            return
        }

        self = .unavailable
    }
}
