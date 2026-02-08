import SwiftUI
import DeltaDoreClient

struct RootTabStoreFactory {
    let make: @MainActor (@escaping @MainActor () -> Void) -> RootTabStore

    static func live(environment: AppEnvironment) -> RootTabStoreFactory {
        RootTabStoreFactory { onDidDisconnect in
            Task {
                await environment.setOnDidDisconnect(onDidDisconnect)
            }

            return RootTabStore(
                dependencies: .init(
                    log: environment.log,
                    preparePersistence: {
                        try? await environment.repository.startIfNeeded()
                        try? await environment.shutterRepository.startIfNeeded()
                    },
                    decodeMessages: {
                        await environment.client.decodedMessages(logger: environment.log)
                    },
                    applyMessage: { message in
                        await environment.repository.applyMessage(message)
                    },
                    sendText: { text in
                        try? await environment.client.send(text: text)
                    },
                    setAppActive: { isActive in
                        await environment.client.setCurrentConnectionAppActive(isActive)
                    },
                    disconnectConnection: {
                        await environment.client.disconnectCurrentConnection()
                    },
                    clearShutterState: {
                        await environment.shutterRepository.clearAll()
                    },
                    clearStoredData: {
                        await environment.client.clearStoredData()
                    },
                    deviceByID: { uniqueId in
                        await environment.repository.device(uniqueId: uniqueId)
                    }
                ),
                onDelegateEvent: { delegateEvent in
                    if case .didDisconnect = delegateEvent {
                        onDidDisconnect()
                    }
                }
            )
        }
    }
}

private struct RootTabStoreFactoryKey: EnvironmentKey {
    static var defaultValue: RootTabStoreFactory {
        RootTabStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var rootTabStoreFactory: RootTabStoreFactory {
        get { self[RootTabStoreFactoryKey.self] }
        set { self[RootTabStoreFactoryKey.self] = newValue }
    }
}
