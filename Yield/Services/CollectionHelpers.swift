import Foundation

extension Array {
    /// Build an O(1) lookup dictionary keyed by the given key path.
    /// Assumes keys are unique — the last element wins on collision.
    /// Replaces scattered uses of
    /// `Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })`.
    func indexed<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Key: Element] {
        Dictionary(uniqueKeysWithValues: map { ($0[keyPath: keyPath], $0) })
    }
}
