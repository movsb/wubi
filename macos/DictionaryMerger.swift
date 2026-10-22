import Foundation

struct DictionaryMergeReport: Codable {
    struct AddedPhrase: Codable {
        let word: String
        let code: String
        let frequency: Double
        private let characterCodes: [String: String]
        var roots: [String: String] {
            Dictionary(word.map { (String($0), characterCodes[String($0)]!) }, uniquingKeysWith: { a, _ in a })
        }
        init(word: String, code: String, frequency: Double, roots: [String: String]) {
            self.word = word; self.code = code; self.frequency = frequency
            characterCodes = roots
        }
        enum CodingKeys: String, CodingKey { case word, code, frequency, roots }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            word = try values.decode(String.self, forKey: .word)
            code = try values.decode(String.self, forKey: .code)
            frequency = try values.decode(Double.self, forKey: .frequency)
            characterCodes = try values.decode([String: String].self, forKey: .roots)
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(word, forKey: .word)
            try values.encode(code, forKey: .code)
            try values.encode(frequency, forKey: .frequency)
            try values.encode(roots, forKey: .roots)
        }
    }
    struct Change: Codable {
        let code: String
        let before: String
        let after: String
        let beforeFrequency: Double
        let afterFrequency: Double
    }
    struct Skipped: Codable {
        let word: String
        let missingCharacters: [String]
    }
    let originalEntries: Int
    let addedPhrases: Int
    let skippedPhrases: Int
    let mergedEntries: Int
    let changedFirstCandidates: Int
    let protectedShortCodes: Int
    let newPhrases: [AddedPhrase]
    let firstCandidateChanges: [Change]
    let skipped: [Skipped]

    // The complete report is on disk; retain only examples in the running input method.
    func summary() -> DictionaryMergeReport {
        .init(originalEntries: originalEntries, addedPhrases: addedPhrases, skippedPhrases: skippedPhrases,
              mergedEntries: mergedEntries, changedFirstCandidates: changedFirstCandidates,
              protectedShortCodes: protectedShortCodes, newPhrases: Array(newPhrases.prefix(30)),
              firstCandidateChanges: Array(firstCandidateChanges.prefix(30)), skipped: Array(skipped.prefix(30)))
    }

    func write(to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        // Encode entries separately so JSONEncoder never builds an enormous object graph.
        let destination = directory.appendingPathComponent("dictionary-merge-report.json")
        let temporary = directory.appendingPathComponent(".merge-report-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
            throw NSError(domain: "Wubi.Report", code: 1)
        }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        func write(_ text: String) throws { try handle.write(contentsOf: Data(text.utf8)) }
        func array<T: Encodable>(_ name: String, _ values: [T]) throws {
            try write(",\n\"" + name + "\":[")
            for (index, value) in values.enumerated() {
                if index > 0 { try write(",") }
                try autoreleasepool { try handle.write(contentsOf: encoder.encode(value)) }
            }
            try write("]")
        }
        try write("{\n\"original_entries\":\(originalEntries),\n\"added_phrases\":\(addedPhrases),\n\"skipped_phrases\":\(skippedPhrases),\n\"merged_entries\":\(mergedEntries),\n\"changed_first_candidates\":\(changedFirstCandidates),\n\"protected_short_codes\":\(protectedShortCodes)")
        try array("new_phrases", newPhrases)
        try array("first_candidate_changes", firstCandidateChanges)
        try array("skipped", skipped)
        try write("\n}")
        try handle.close()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
        var lines = ["# 五笔与拼音词库合并报告", "",
                     "- 原五笔词条：\(originalEntries)", "- 新增词语：\(addedPhrases)",
                     "- 跳过词语：\(skippedPhrases)", "- 保留顺序的简码组：\(protectedShortCodes)",
                     "- 首选词发生变化的全码组：\(changedFirstCandidates)", "",
                     "## 新增高频词示例", "", "| 词语 | 五笔编码 | 拼音词频 |", "| --- | --- | --- |"]
        for item in newPhrases.prefix(30) { lines.append("| \(item.word) | \(item.code) | \(item.frequency) |") }
        lines += ["", "## 全码首选变化示例", "", "| 编码 | 原首选 | 新首选 |", "| --- | --- | --- |"]
        for item in firstCandidateChanges.prefix(30) { lines.append("| \(item.code) | \(item.before) | \(item.after) |") }
        lines += ["", "完整记录和跳过原因见同名 JSON 文件。", ""]
        try lines.joined(separator: "\n").write(to: directory.appendingPathComponent("dictionary-merge-report.md"), atomically: true, encoding: .utf8)
    }
}

struct DictionaryMerger {
    struct Result {
        let dictionary: WubiDictionary
        let report: DictionaryMergeReport
    }
    private struct Entry {
        let row: DictionaryRow
        let order: Int
    }

    static func phraseCode(_ word: String, roots: [String: String]) -> String? {
        let chars = word.map(String.init)
        guard chars.count >= 2, chars.allSatisfy({ isHanzi($0) && (roots[$0]?.count ?? 0) >= 2 }) else { return nil }
        let codes = chars.map { roots[$0]! }
        if chars.count == 2 { return String(codes[0].prefix(2)) + String(codes[1].prefix(2)) }
        if chars.count == 3 { return String(codes[0].prefix(1)) + String(codes[1].prefix(1)) + String(codes[2].prefix(2)) }
        return [codes[0], codes[1], codes[2], codes.last!].map { String($0.prefix(1)) }.joined()
    }

    static func merge(wubiRows: [DictionaryRow], pinyin: PinyinDictionary) -> Result {
        var original: [Entry] = []
        var seen: [String: Set<String>] = [:]
        var roots: [String: String] = [:]
        var priorities: [String: (Int, Double, Int)] = [:]
        for row in wubiRows {
            guard !row.word.isEmpty, let code = row.wubiCode,
                  seen[code, default: []].insert(row.word).inserted else { continue }
            let entry = Entry(row: DictionaryRow(word: row.word, code: code, weight: row.weight), order: original.count)
            original.append(entry)
            if row.word.count == 1, code.count >= 2, !code.hasPrefix("z") {
                let priority = (code.count, row.weight, -entry.order)
                if priorities[row.word] == nil || priority > priorities[row.word]! {
                    roots[row.word] = code
                    priorities[row.word] = priority
                }
            }
        }
        let existing = Set(original.map { $0.row.word })
        var added: [Entry] = []
        var skipped: [DictionaryMergeReport.Skipped] = []
        for word in pinyin.wordsInOrder where !existing.contains(word) && word.count >= 2 {
            guard let code = phraseCode(word, roots: roots) else {
                skipped.append(.init(word: word, missingCharacters: Set(word.map(String.init)).filter { roots[$0] == nil }.sorted()))
                continue
            }
            added.append(Entry(row: DictionaryRow(word: word, code: code, weight: 0), order: original.count + added.count))
        }
        var before = Dictionary(grouping: original, by: { $0.row.code })
        for code in Array(before.keys) {
            before[code]?.sort { $0.row.weight == $1.row.weight ? $0.order < $1.order : $0.row.weight > $1.row.weight }
        }
        var after = before
        for entry in added { after[entry.row.code, default: []].append(entry) }
        for code in Array(after.keys) where code.count == 4 {
            // Explicit tie-breaker keeps both original ranking and generated source order stable.
            let values = after[code]!.enumerated().sorted {
                let a = pinyin.frequencies[$0.element.row.word] ?? 0
                let b = pinyin.frequencies[$1.element.row.word] ?? 0
                return a == b ? $0.offset < $1.offset : a > b
            }
            after[code] = values.map(\.element)
        }
        var changes: [DictionaryMergeReport.Change] = []
        for (code, values) in before {
            let old = values[0].row.word
            let new = after[code]![0].row.word
            if old != new {
                changes.append(.init(code: code, before: old, after: new,
                                     beforeFrequency: pinyin.frequencies[old] ?? 0, afterFrequency: pinyin.frequencies[new] ?? 0))
            }
        }
        changes.sort { $0.afterFrequency == $1.afterFrequency ? $0.code < $1.code : $0.afterFrequency > $1.afterFrequency }
        let rankedAdded = added.sorted {
            let a = pinyin.frequencies[$0.row.word] ?? 0
            let b = pinyin.frequencies[$1.row.word] ?? 0
            return a == b ? $0.order < $1.order : a > b
        }
        let report = DictionaryMergeReport(
            originalEntries: original.count, addedPhrases: added.count, skippedPhrases: skipped.count,
            mergedEntries: original.count + added.count, changedFirstCandidates: changes.count,
            protectedShortCodes: before.keys.filter { $0.count < 4 }.count,
            newPhrases: rankedAdded.map { entry in
                .init(word: entry.row.word, code: entry.row.code, frequency: pinyin.frequencies[entry.row.word] ?? 0,
                      roots: roots)
            }, firstCandidateChanges: changes, skipped: skipped)
        var rankedRows: [DictionaryRow] = []
        for code in after.keys.sorted() {
            let values = after[code]!
            for (rank, entry) in values.enumerated() {
                rankedRows.append(DictionaryRow(word: entry.row.word, code: code, weight: Double(values.count - rank)))
            }
        }
        return Result(dictionary: WubiDictionary(rows: rankedRows, completionFrequencies: pinyin.frequencies), report: report)
    }

    private static func isHanzi(_ text: String) -> Bool {
        guard text.unicodeScalars.count == 1, let value = text.unicodeScalars.first?.value else { return false }
        return [(0x3400...0x4DBF), (0x4E00...0x9FFF), (0xF900...0xFAFF),
                (0x20000...0x2FA1F), (0x30000...0x323AF)].contains { $0.contains(Int(value)) }
    }
}
