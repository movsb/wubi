import Foundation

struct DictionaryRow {
    let word: String
    let code: String
    let weight: Double

    static func readExcludedWords(_ url: URL) throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let contents = try String(contentsOf: url, encoding: .utf8)
        return Set(contents.components(separatedBy: .newlines).compactMap { raw in
            let word = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{feff}")))
            return word.isEmpty ? nil : word
        })
    }

    static func exclude(_ word: String, at url: URL) throws {
        guard !word.isEmpty, word.rangeOfCharacter(from: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "#"))) == nil else {
            throw NSError(domain: "Wubi.Dictionary", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "无法排除无效词条"])
        }
        guard try !readExcludedWords(url).contains(word) else { return }
        var contents = FileManager.default.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : ""
        if !contents.isEmpty && !contents.hasSuffix("\n") && !contents.hasSuffix("\r") { contents += "\n" }
        contents += word + "\n"
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    static func readUserText(_ url: URL) throws -> [DictionaryRow] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        var rows: [DictionaryRow] = []
        let lines = contents.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for (index, raw) in lines.components(separatedBy: "\n").enumerated() {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{feff}")))
            if line.isEmpty { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let syllables = fields.count >= 2 ? fields[1].lowercased().split(whereSeparator: { $0 == " " || $0 == "'" }) : []
            guard fields.count == 2, !fields[0].isEmpty,
                  !syllables.isEmpty, syllables.allSatisfy({ $0.utf8.allSatisfy { (97...122).contains($0) } }) else {
                throw NSError(domain: "Wubi.Dictionary", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "\(url.lastPathComponent) 第 \(index + 1) 行格式错误，应为：词语<Tab>拼音",
                ])
            }
            rows.append(.init(word: fields[0], code: syllables.joined(separator: " "), weight: 0))
        }
        return rows
    }

    static func read(_ url: URL) throws -> [DictionaryRow] {
        var contents = try String(contentsOf: url, encoding: .utf8)
        var rows: [DictionaryRow] = []
        // Scan without materializing an array containing every line in the source dictionary.
        contents.withUTF8 { bytes in
            func consume(_ start: Int, _ end: Int) {
                guard start < end else { return }
                guard bytes[start] != 35, bytes[start] != 32 else { return }
                let line = String(decoding: bytes[start..<end], as: UTF8.self)
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count >= 2, !fields[0].isEmpty else { return }
                let weight = fields.count > 2 ? Double(fields[2].filter { $0 != "%" }) ?? 0 : 0
                rows.append(DictionaryRow(word: String(fields[0]), code: String(fields[1]), weight: weight.isFinite ? weight : 0))
            }
            var start = 0
            for offset in bytes.indices where bytes[offset] == 10 || bytes[offset] == 13 {
                consume(start, offset)
                start = offset + 1
            }
            consume(start, bytes.count)
        }
        return rows
    }

    var wubiCode: String? {
        let value = code.lowercased()
        return (1...4).contains(value.count) && value.utf8.allSatisfy { (97...122).contains($0) } ? value : nil
    }
}
