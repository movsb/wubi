import Foundation

struct WubiDictionary {
    private(set) var count = 0
    private var prefixIndex = CandidateIndex(items: [])
    private var reverseIndex = CandidateIndex(items: [])

    init(indexURL: URL, count: Int) throws {
        self.count = count
        prefixIndex = try CandidateIndex(mappedURL: indexURL)
        reverseIndex = try CandidateIndex(mappedURL: indexURL.appendingPathExtension("reverse"))
    }

    func writeIndex(to url: URL) throws {
        try prefixIndex.write(to: url)
        try reverseIndex.write(to: url.appendingPathExtension("reverse"))
    }

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
            for value in values {
                items.append(.init(text: value.text, code: code,
                    weight: completionFrequencies.isEmpty ? value.weight : completionFrequencies[value.text] ?? 0,
                    order: items.count))
            }
        }
        prefixIndex = CandidateIndex(items: items)
        // Prefer the shortest normal code, keeping the reverse index compact and mappable.
        var codes: [String: String] = [:]
        for item in items {
            if let previous = codes[item.text] {
                let previousNormal = !previous.hasPrefix("z")
                let normal = !item.code.hasPrefix("z")
                if previousNormal != normal {
                    if !normal { continue }
                } else if previous.count < item.code.count || (previous.count == item.code.count && previous <= item.code) {
                    continue
                }
            }
            codes[item.text] = item.code
        }
        reverseIndex = CandidateIndex(items: codes.map {
            .init(text: $0.value, code: $0.key, weight: 0, order: 0)
        })
    }

    func lookup(_ code: String) -> [String] { prefixIndex.lookup(code.lowercased()) }

    func reverseLookup(_ text: String) -> String? { reverseIndex.lookup(text).first }

    func candidates(prefix: String) -> [InputCandidate] {
        guard prefix.utf8.allSatisfy({ (97...122).contains($0) }) else { return [] }
        return prefixIndex.candidates(prefix: prefix)
    }
}
