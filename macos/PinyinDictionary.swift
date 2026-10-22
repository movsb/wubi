import Foundation

struct PinyinDictionary {
    private(set) var count = 0
    private(set) var frequencies: [String: Double] = [:]
    private(set) var wordsInOrder: [String] = []
    private var compactIndex = CandidateIndex(items: [])
    private var syllableIndex = CandidateIndex(items: [])

    init(indexDirectory: URL, count: Int) throws {
        self.count = count
        compactIndex = try CandidateIndex(mappedURL: indexDirectory.appendingPathComponent("pinyin.index"))
        syllableIndex = try CandidateIndex(mappedURL: indexDirectory.appendingPathComponent("syllables.index"))
    }

    func writeIndices(to directory: URL) throws {
        try compactIndex.write(to: directory.appendingPathComponent("pinyin.index"))
        try syllableIndex.write(to: directory.appendingPathComponent("syllables.index"))
    }

    init(url: URL) throws {
        self.init(rows: try DictionaryRow.read(url))
    }

    init(rows: [DictionaryRow]) {
        var seen = Set<String>()
        var compact: [CandidateIndex.Item] = []
        var syllableItems: [CandidateIndex.Item] = []
        for row in rows {
            guard !row.word.isEmpty else { continue }
            let syllables = row.code.split(whereSeparator: { $0 == " " || $0 == "'" })
            guard !syllables.isEmpty, syllables.allSatisfy({ $0.utf8.allSatisfy { (97...122).contains($0) } }) else { continue }
            let spelling = syllables.joined(separator: "'")
            if frequencies[row.word] == nil { wordsInOrder.append(row.word) }
            frequencies[row.word] = max(row.weight, frequencies[row.word] ?? 0)
            guard seen.insert(row.word + "\t" + spelling).inserted else { continue }
            compact.append(.init(text: row.word, code: syllables.joined(), weight: row.weight, order: count))
            syllableItems.append(.init(text: row.word, code: spelling, weight: row.weight, order: count))
            count += 1
        }
        compactIndex = CandidateIndex(items: compact, rankExactByWeight: true)
        syllableIndex = CandidateIndex(items: syllableItems, rankExactByWeight: true)
    }

    func lookup(_ code: String) -> [String] {
        guard !code.isEmpty, code.utf8.allSatisfy({ (97...122).contains($0) || $0 == 39 }) else { return [] }
        return code.contains("'") ? syllableIndex.lookup(code) : compactIndex.lookup(code)
    }

    mutating func discardMergeMetadata() {
        frequencies = [:]
        wordsInOrder = []
    }

    func candidates(prefix: String) -> [InputCandidate] {
        guard prefix.utf8.allSatisfy({ (97...122).contains($0) || $0 == 39 }) else { return [] }
        return prefix.contains("'") ? syllableIndex.candidates(prefix: prefix) : compactIndex.candidates(prefix: prefix)
    }
}
