import Foundation

struct InputCandidate: Equatable {
    let text: String
    let remainingCode: String
}

// Sorted prefix index with a small per-snapshot cache, avoiding a full scan per key.
final class CandidateIndex {
    struct Item {
        let text: String
        let code: String
        let weight: Double
        let order: Int
    }
    private let items: [Item]
    private var cache: [String: [InputCandidate]] = [:]

    init(items: [Item]) {
        self.items = items.sorted { $0.code == $1.code ? $0.order < $1.order : $0.code < $1.code }
    }

    func candidates(prefix: String) -> [InputCandidate] {
        guard !prefix.isEmpty else { return [] }
        if let saved = cache[prefix] { return saved }
        var low = 0
        var high = items.count
        while low < high {
            let middle = (low + high) / 2
            if items[middle].code < prefix { low = middle + 1 }
            else { high = middle }
        }
        var exact: [Item] = []
        var completions: [Item] = []
        var position = low
        while position < items.count && items[position].code.hasPrefix(prefix) {
            let item = items[position]
            if item.code == prefix { exact.append(item) }
            else { completions.append(item) }
            position += 1
        }
        completions.sort {
            if $0.weight != $1.weight { return $0.weight > $1.weight }
            if $0.code.count != $1.code.count { return $0.code.count < $1.code.count }
            if $0.code != $1.code { return $0.code < $1.code }
            return $0.order < $1.order
        }
        var seen = Set<String>()
        let result = (exact + completions).compactMap { item -> InputCandidate? in
            guard seen.insert(item.text).inserted else { return nil }
            return InputCandidate(text: item.text, remainingCode: String(item.code.dropFirst(prefix.count)))
        }
        if cache.count >= 32 { cache.removeAll(keepingCapacity: true) }
        cache[prefix] = result
        return result
    }
}
