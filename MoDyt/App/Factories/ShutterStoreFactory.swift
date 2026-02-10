import SwiftUI
import DeltaDoreClient

struct ShutterStoreFactory {
    let make: @MainActor (String) -> ShutterStore

    static func live(environment: AppEnvironment) -> ShutterStoreFactory {
        ShutterStoreFactory { uniqueId in
            ShutterStore(
                uniqueId: uniqueId,
                initialDevice: nil,
                dependencies: .init(
                    observeShutter: { uniqueId in
                        await environment.shutterRepository
                            .observeShutter(uniqueId: uniqueId)
                            .removeDuplicates(by: ShutterSnapshot.areEquivalentForUI)
                    },
                    setTarget: { uniqueId, targetStep, originStep in
                        await environment.shutterRepository.setTarget(
                            uniqueId: uniqueId,
                            targetStep: targetStep,
                            originStep: originStep
                        )
                    },
                    sendCommand: { uniqueId, key, value in
                        await environment.sendDeviceCommand(uniqueId, key, value)
                    }
                )
            )
        }
    }
}

private struct ShutterStoreFactoryKey: EnvironmentKey {
    static var defaultValue: ShutterStoreFactory {
        ShutterStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var shutterStoreFactory: ShutterStoreFactory {
        get { self[ShutterStoreFactoryKey.self] }
        set { self[ShutterStoreFactoryKey.self] = newValue }
    }
}
