import Foundation

actor TydomDeviceCacheStore {
    private var devices: [TydomDeviceIdentifier: TydomDeviceCacheEntry] = [:]

    init() {}

    func deviceInfo(for identifier: TydomDeviceIdentifier) async -> TydomDeviceInfo? {
        guard let entry = devices[identifier],
              let name = entry.name, name.isEmpty == false,
              let usage = entry.usage, usage.isEmpty == false
        else {
            return nil
        }
        return TydomDeviceInfo(name: name, usage: usage, metadata: entry.metadata)
    }

    func upsert(_ entry: TydomDeviceCacheEntry) async {
        var current = devices[entry.identifier] ?? TydomDeviceCacheEntry(identifier: entry.identifier)
        if let name = entry.name { current.name = name }
        if let usage = entry.usage { current.usage = usage }
        if let metadata = entry.metadata {
            var mergedMetadata = current.metadata ?? [:]
            for (key, value) in metadata {
                mergedMetadata[key] = value
            }
            current.metadata = mergedMetadata
        }
        devices[entry.identifier] = current
    }
}
