import Foundation

struct PinyinDictionary {
    private struct Entry {
        let text: String
        let spelling: String
        let weight: Double
        let order: Int
    }
    private var entries: [String: [Entry]] = [:]
    private(set) var count = 0
    private(set) var frequencies: [String: Double] = [:]
    private(set) var wordsInOrder: [String] = []

    init(url: URL) throws {
        self.init(rows: try DictionaryRow.read(url))
    }

    init(rows: [DictionaryRow]) {
        var seen = Set<String>()
        for row in rows {
            guard !row.word.isEmpty else { continue }
            let syllables = row.code.split(whereSeparator: { $0 == " " || $0 == "'" })
            guard !syllables.isEmpty, syllables.allSatisfy({ $0.utf8.allSatisfy { (97...122).contains($0) } }) else { continue }
            let spelling = syllables.joined(separator: "'")
            if frequencies[row.word] == nil { wordsInOrder.append(row.word) }
            frequencies[row.word] = max(row.weight, frequencies[row.word] ?? 0)
            guard seen.insert(row.word + "\t" + spelling).inserted else { continue }
            entries[syllables.joined(), default: []].append(Entry(
                text: row.word, spelling: spelling, weight: row.weight, order: count))
            count += 1
        }
        for key in Array(entries.keys) {
            entries[key]?.sort { $0.weight == $1.weight ? $0.order < $1.order : $0.weight > $1.weight }
        }
    }

    func lookup(_ code: String) -> [String] {
        guard !code.isEmpty, code.utf8.allSatisfy({ (97...122).contains($0) || $0 == 39 }) else { return [] }
        let values = entries[code.replacingOccurrences(of: "'", with: "")] ?? []
        var seen = Set<String>()
        return values.compactMap { entry in
            if code.contains("'"), entry.spelling != code { return nil }
            return seen.insert(entry.text).inserted ? entry.text : nil
        }
    }
}
