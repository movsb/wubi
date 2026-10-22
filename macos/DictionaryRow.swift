import Foundation

struct DictionaryRow {
    let word: String
    let code: String
    let weight: Double

    static func read(_ url: URL) throws -> [DictionaryRow] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        var started = false
        var rows: [DictionaryRow] = []
        for line in contents.components(separatedBy: .newlines) {
            if !started {
                if line.trimmingCharacters(in: .whitespaces) == "..." { started = true }
                continue
            }
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(" ") { continue }
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 2, !fields[0].isEmpty else { continue }
            let weight = fields.count > 2 ? Double(fields[2].replacingOccurrences(of: "%", with: "")) ?? 0 : 0
            rows.append(DictionaryRow(word: fields[0], code: fields[1], weight: weight.isFinite ? weight : 0))
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
