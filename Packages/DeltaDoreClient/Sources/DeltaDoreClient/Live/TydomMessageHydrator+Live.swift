import Foundation

extension TydomMessageHydratorDependencies {
    static func live(
        _ cache: TydomDeviceCacheStore = TydomDeviceCacheStore(),
        scenarioStore: TydomScenarioMetadataStore = TydomScenarioMetadataStore(),
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> TydomMessageHydratorDependencies {
        TydomMessageHydratorDependencies(
            deviceInfo: { uniqueId in
                await cache.deviceInfo(for: uniqueId)
            },
            scenarioMetadata: { scenarioId in
                await scenarioStore.metadata(for: scenarioId)
            },
            applyCacheMutation: { mutation in
                switch mutation {
                case .deviceEntry(let entry):
                    await cache.upsert(entry)
                case .scenarioMetadata(let metadata):
                    await scenarioStore.upsert(metadata)
                }
            },
            log: log
        )
    }
}

extension TydomMessageHydrator {
    static func live(
        cache: TydomDeviceCacheStore = TydomDeviceCacheStore(),
        scenarioStore: TydomScenarioMetadataStore = TydomScenarioMetadataStore(),
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> TydomMessageHydrator {
        TydomMessageHydrator(dependencies: .live(cache, scenarioStore: scenarioStore, log: log))
    }
}
