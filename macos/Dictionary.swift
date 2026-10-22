import Foundation

struct WubiDictionary {
    private var entries: [String: [String]] = [:]
    private(set) var count = 0

    init(urls: [URL]) throws {
        struct Entry { let text: String; let weight: Double; let order: Int }
        var grouped: [String: [Entry]] = [:]
        var seen: [String: Set<String>] = [:]
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let contents = try String(contentsOf: url, encoding: .utf8)
            var started = false
            for line in contents.components(separatedBy: .newlines) {
                if !started { if line.trimmingCharacters(in: .whitespaces) == "..." { started = true }; continue }
                if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(" ") { continue }
                let fields = line.components(separatedBy: "\t")
                guard fields.count >= 2 else { continue }
                let code = fields[1].lowercased()
                guard !fields[0].isEmpty, (1...4).contains(code.count), code.utf8.allSatisfy({ (97...122).contains($0) }) else { continue }
                guard seen[code, default: []].insert(fields[0]).inserted else { continue }
                let weight = fields.count > 2 ? Double(fields[2].replacingOccurrences(of: "%", with: "")) ?? 0 : 0
                grouped[code, default: []].append(Entry(text: fields[0], weight: weight, order: count))
                count += 1
            }
        }
        for (code, values) in grouped {
            entries[code] = values.sorted { $0.weight == $1.weight ? $0.order < $1.order : $0.weight > $1.weight }.map(\.text)
        }
    }

    func lookup(_ code: String) -> [String] { entries[code.lowercased()] ?? [] }
}
