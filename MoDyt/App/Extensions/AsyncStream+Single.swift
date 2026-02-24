extension AsyncStream where Element: Sendable {
    static func single(_ elemet: Element) -> Self {
        AsyncStream { continuation in
            continuation.yield(elemet)
            continuation.finish()
        }
    }
}
