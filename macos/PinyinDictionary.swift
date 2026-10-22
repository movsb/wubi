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

    init(url: URL) throws {
        let contents = try String(contentsOf: url, encoding: .utf8)
        var started = false
        var seen = Set<String>()
        for line in contents.components(separatedBy: .newlines) {
            if !started {
                if line.trimmingCharacters(in: .whitespaces) == "..." { started = true }
                continue
            }
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(" ") { continue }
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 2, !fields[0].isEmpty else { continue }
            let syllables = fields[1].split(whereSeparator: { $0 == " " || $0 == "'" })
            guard !syllables.isEmpty, syllables.allSatisfy({ $0.utf8.allSatisfy { (97...122).contains($0) } }) else { continue }
            let spelling = syllables.joined(separator: "'")
            guard seen.insert(fields[0] + "\t" + spelling).inserted else { continue }
            let weight = fields.count > 2 ? Double(fields[2]) ?? 0 : 0
            entries[syllables.joined(), default: []].append(Entry(
                text: fields[0], spelling: spelling, weight: weight, order: count))
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
