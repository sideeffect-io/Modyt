import SwiftUI

struct LightStoreFactory {
    let make: @MainActor (String) -> LightStore

    static func live(environment: AppEnvironment) -> LightStoreFactory {
        LightStoreFactory { uniqueId in
            LightStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    observeLight: { uniqueId in
                        if isGroupIdentifier(uniqueId) {
                            let groupUniqueId = makeGroupUniqueId(from: uniqueId)
                            return await environment.groupRepository.observeGroupControlDevice(uniqueId: groupUniqueId)
                        }
                        return await environment.repository.observeDevice(uniqueId: uniqueId)
                    },
                    applyOptimisticChanges: { uniqueId, changes in
                        if isGroupIdentifier(uniqueId) {
                            let groupUniqueId = makeGroupUniqueId(from: uniqueId)
                            await environment.groupRepository.applyOptimisticControlChanges(
                                uniqueId: groupUniqueId,
                                changes: changes
                            )
                        } else {
                            await environment.repository.applyOptimisticUpdates(
                                uniqueId: uniqueId,
                                changes: changes
                            )
                        }
                    },
                    sendCommand: { uniqueId, key, value in
                        let commandUniqueID = isGroupIdentifier(uniqueId)
                            ? makeGroupUniqueId(from: uniqueId)
                            : uniqueId
                        await environment.sendDeviceCommand(commandUniqueID, key, value)
                    }
                )
            )
        }
    }

    private static func isGroupIdentifier(_ uniqueId: String) -> Bool {
        GroupRecord.isGroupUniqueId(uniqueId) || Int(uniqueId) != nil
    }

    private static func makeGroupUniqueId(from uniqueId: String) -> String {
        if GroupRecord.isGroupUniqueId(uniqueId) {
            return uniqueId
        }

        guard let groupID = Int(uniqueId) else {
            return uniqueId
        }

        return GroupRecord.uniqueId(for: groupID)
    }
}

private struct LightStoreFactoryKey: EnvironmentKey {
    static var defaultValue: LightStoreFactory {
        LightStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var lightStoreFactory: LightStoreFactory {
        get { self[LightStoreFactoryKey.self] }
        set { self[LightStoreFactoryKey.self] = newValue }
    }
}
