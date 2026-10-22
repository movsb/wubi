import Foundation

let manualPhraseSavedNotification = Notification.Name("com.movsb.inputmethod.Wubi.manualPhraseSaved")

// Mixed-radix enumeration keeps even many polyphonic characters cheap to page through.
struct ManualReadings {
    let syllables: [[String]]
    let count: Int

    init(word: String, readings: (Character) -> [String]) throws {
        guard !word.isEmpty, word.unicodeScalars.allSatisfy({
            (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
                || (0x20000...0x323AF).contains($0.value)
        }) else { throw Self.error("请输入汉字词语") }
        var values: [[String]] = []
        var total = 1
        for character in word {
            let options = readings(character)
            guard !options.isEmpty else { throw Self.error("找不到「\(character)」的拼音") }
            let product = total.multipliedReportingOverflow(by: options.count)
            guard !product.overflow else { throw Self.error("拼音组合过多，请缩短词语") }
            total = product.partialValue
            values.append(options)
        }
        syllables = values
        count = total
    }

    func spelling(at index: Int) -> String? {
        guard index >= 0 && index < count else { return nil }
        var remainder = index
        var result: [String] = []
        for options in syllables.reversed() {
            result.append(options[remainder % options.count])
            remainder /= options.count
        }
        return result.reversed().joined(separator: " ")
    }

    static func error(_ text: String) -> NSError {
        NSError(domain: "Wubi.ManualPhrase", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }

    static func save(word: String, spelling: String, to url: URL) throws {
        let normalized = spelling.split(separator: " ").joined(separator: " ")
        _ = try ManualReadings(word: word, readings: { _ in ["a"] })
        guard normalized.split(separator: " ").count == word.count,
              normalized.utf8.allSatisfy({ (97...122).contains($0) || $0 == 32 }) else {
            throw error("拼音格式无效")
        }
        let exists = FileManager.default.fileExists(atPath: url.path)
        let rows = exists ? try DictionaryRow.readUserText(url) : []
        guard !rows.contains(where: { $0.word == word && $0.code == normalized }) else { return }
        var contents = exists ? try String(contentsOf: url, encoding: .utf8) : ""
        if !contents.isEmpty && !contents.hasSuffix("\n") { contents += "\n" }
        contents += word + "\t" + normalized + "\n"
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
