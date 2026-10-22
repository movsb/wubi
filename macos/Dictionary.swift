import Foundation

struct WubiDictionary {
    private var entries: [String: [String]] = [:]
    private(set) var count = 0

    init(urls: [URL]) throws {
        let rows = try urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.flatMap { try DictionaryRow.read($0) }
        self.init(rows: rows)
    }

    init(rows: [DictionaryRow]) {
        struct Entry { let text: String; let weight: Double; let order: Int }
        var grouped: [String: [Entry]] = [:]
        var seen: [String: Set<String>] = [:]
        for row in rows {
            guard !row.word.isEmpty, let code = row.wubiCode else { continue }
            guard seen[code, default: []].insert(row.word).inserted else { continue }
            grouped[code, default: []].append(Entry(text: row.word, weight: row.weight, order: count))
            count += 1
        }
        for (code, values) in grouped {
            entries[code] = values.sorted { $0.weight == $1.weight ? $0.order < $1.order : $0.weight > $1.weight }.map(\.text)
        }
    }

    func lookup(_ code: String) -> [String] { entries[code.lowercased()] ?? [] }
}
