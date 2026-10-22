import Foundation

struct WubiDictionary {
    private var entries: [String: [String]] = [:]
    private(set) var count = 0
    private var prefixIndex = CandidateIndex(items: [])

    init(urls: [URL]) throws {
        let rows = try urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.flatMap { try DictionaryRow.read($0) }
        self.init(rows: rows)
    }

    init(rows: [DictionaryRow], completionFrequencies: [String: Double] = [:]) {
        struct Entry { let text: String; let weight: Double; let order: Int }
        var grouped: [String: [Entry]] = [:]
        var seen: [String: Set<String>] = [:]
        for row in rows {
            guard !row.word.isEmpty, let code = row.wubiCode else { continue }
            guard seen[code, default: []].insert(row.word).inserted else { continue }
            grouped[code, default: []].append(Entry(text: row.word, weight: row.weight, order: count))
            count += 1
        }
        var items: [CandidateIndex.Item] = []
        for code in grouped.keys.sorted() {
            let values = grouped[code]!.sorted { $0.weight == $1.weight ? $0.order < $1.order : $0.weight > $1.weight }
            entries[code] = values.map(\.text)
            for value in values {
                items.append(.init(text: value.text, code: code,
                    weight: completionFrequencies.isEmpty ? value.weight : completionFrequencies[value.text] ?? 0,
                    order: items.count))
            }
        }
        prefixIndex = CandidateIndex(items: items)
    }

    func lookup(_ code: String) -> [String] { entries[code.lowercased()] ?? [] }

    func candidates(prefix: String) -> [InputCandidate] {
        guard prefix.utf8.allSatisfy({ (97...122).contains($0) }) else { return [] }
        return prefixIndex.candidates(prefix: prefix)
    }
}
