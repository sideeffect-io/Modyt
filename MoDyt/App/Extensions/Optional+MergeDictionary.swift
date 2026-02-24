extension Optional{
    func mergedDictionary<Value: Equatable>(
        incoming: [String: Value]?
    ) -> [String: Value] where Wrapped == Dictionary<String, Value> {
        var merged = self ?? [:]

        guard let incoming else {
            return merged
        }

        for (key, value) in incoming {
            merged[key] = value
        }

        return merged
    }
}

extension Dictionary where Key == String, Value: Equatable {
    func mergedDictionary(
        incoming: [String: Value]?
    ) -> [String: Value] {
        var merged = self

        guard let incoming else {
            return merged
        }

        for (key, value) in incoming {
            merged[key] = value
        }

        return merged
    }
}

