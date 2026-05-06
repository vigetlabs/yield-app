import Foundation

extension Array {
    /// Build an O(1) lookup dictionary keyed by the given closure.
    /// Assumes keys are unique — the last element wins on collision.
    /// Replaces scattered uses of
    /// `Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })`.
    ///
    /// This used to take a `KeyPath<Element, Key>` argument. We
    /// rewrote it to a closure after a launch crash on macOS 14.6.1
    /// (`EXC_BREAKPOINT` in `AnyKeyPath` equality) — the Swift
    /// runtime caches KeyPath instances built inside generic
    /// specializations and the cache's equality path is buggy on
    /// older 14.x. Closures bypass that path.
    func indexed<Key: Hashable>(by key: (Element) -> Key) -> [Key: Element] {
        Dictionary(uniqueKeysWithValues: map { (key($0), $0) })
    }
}
