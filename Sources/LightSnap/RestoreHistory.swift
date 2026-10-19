import Foundation

struct RestoreHistory<Key: Equatable> {
    struct Entry { let key: Key; let frame: CGRect }
    private(set) var entries: [Entry] = []
    let capacity: Int
    init(capacity: Int = 128) { self.capacity = max(1, capacity) }
    func frame(for key: Key) -> CGRect? { entries.first { $0.key == key }?.frame }
    mutating func remember(_ key: Key, frame: CGRect) {
        guard self.frame(for: key) == nil else { return }
        if entries.count >= capacity { entries.removeFirst() }
        entries.append(Entry(key: key, frame: frame))
    }
    mutating func remove(_ key: Key) { entries.removeAll { $0.key == key } }
    mutating func prune(_ shouldRemove: (Key) -> Bool) { entries.removeAll { shouldRemove($0.key) } }
}
