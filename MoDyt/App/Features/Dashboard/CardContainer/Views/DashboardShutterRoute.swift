import Foundation

enum DashboardShutterRoute: Equatable {
    case unavailable
    case single(DeviceIdentifier)
    case group([DeviceIdentifier])

    init(favorite: FavoriteItem) {
        guard favorite.controlKind == .shutter else {
            self = .unavailable
            return
        }

        if favorite.isGroup {
            let identifiers = favorite.shutterIdentifiers.uniquePreservingOrder()
            self = identifiers.isEmpty ? .unavailable : .group(identifiers)
            return
        }

        if let deviceId = favorite.controlDeviceIdentifier {
            self = .single(deviceId)
            return
        }

        if let deviceId = favorite.shutterIdentifiers.uniquePreservingOrder().first {
            self = .single(deviceId)
            return
        }

        self = .unavailable
    }
}
