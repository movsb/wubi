import Foundation

struct DictionaryRow {
    let word: String
    let code: String
    let weight: Double

    static func read(_ url: URL) throws -> [DictionaryRow] {
        var contents = try String(contentsOf: url, encoding: .utf8)
        var started = false
        var rows: [DictionaryRow] = []
        // Scan without materializing an array containing every line in the source dictionary.
        contents.withUTF8 { bytes in
            func consume(_ start: Int, _ end: Int) {
                guard start < end else { return }
                if !started {
                    let line = String(decoding: bytes[start..<end], as: UTF8.self)
                    if line.trimmingCharacters(in: .whitespaces) == "..." { started = true }
                    return
                }
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
        guard started else {
            throw NSError(domain: "Wubi.Dictionary", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(url.lastPathComponent) 缺少 Rime 码表分隔符 ...",
            ])
        }
        return rows
    }

    var wubiCode: String? {
        let value = code.lowercased()
        return (1...4).contains(value.count) && value.utf8.allSatisfy { (97...122).contains($0) } ? value : nil
    }
}
