extension Collection where Element: Hashable {
    func uniquePreservingOrder() -> [Element] {
        var seen: Set<Element> = []
        var result: [Element] = []

        for element in self where seen.contains(element) == false {
            seen.insert(element)
            result.append(element)
        }

        return result
    }
}
