import Foundation

struct InputCandidate: Equatable {
    let text: String
    let remainingCode: String
}

// Keep UTF-8 bytes and fixed-size offsets, rather than millions of heap-backed Strings.
final class CandidateIndex {
    struct Item {
        let text: String
        let code: String
        let weight: Double
        let order: Int
    }
    private struct Record {
        let textStart: UInt32
        let textLength: UInt32
        let codeStart: UInt32
        let codeLength: UInt32
        let weight: Double
    }
    private var bytes: [UInt8] = []
    private var records: [Record] = []
    private var mapped: Data?
    private var mappedCount = 0
    private var byteStart = 0
    private var recordCount: Int { mapped == nil ? records.count : mappedCount }
    private func record(_ index: Int) -> Record {
        guard let mapped else { return records[index] }
        return mapped.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24 + index * MemoryLayout<Record>.stride, as: Record.self) }
    }
    private func byte(_ offset: Int) -> UInt8 { mapped?[byteStart + offset] ?? bytes[offset] }
    private func string(_ start: Int, _ length: Int) -> String {
        if let mapped { return String(decoding: mapped[(byteStart + start)..<(byteStart + start + length)], as: UTF8.self) }
        return String(decoding: bytes[start..<(start + length)], as: UTF8.self)
    }

    init(mappedURL: URL) throws {
        let data = try Data(contentsOf: mappedURL, options: .alwaysMapped)
        func invalid() -> NSError { NSError(domain: "Wubi.Index", code: 1, userInfo: [NSLocalizedDescriptionKey: "索引文件损坏：" + mappedURL.lastPathComponent]) }
        guard data.count >= 24, data.prefix(8) == Data("WUBIIDX1".utf8) else { throw invalid() }
        let count = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self) }
        let size = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt64.self) }
        guard count <= UInt64((data.count - 24) / MemoryLayout<Record>.stride),
              size == UInt64(data.count - 24) - count * UInt64(MemoryLayout<Record>.stride) else { throw invalid() }
        mapped = data
        mappedCount = Int(count)
        byteStart = 24 + mappedCount * MemoryLayout<Record>.stride
        for index in 0..<mappedCount {
            let value = record(index)
            guard UInt64(value.textStart) + UInt64(value.textLength) <= size,
                  UInt64(value.codeStart) + UInt64(value.codeLength) <= size else { throw invalid() }
        }
    }

    func write(to url: URL) throws {
        if let mapped { try mapped.write(to: url, options: .atomic); return }
        var data = Data("WUBIIDX1".utf8)
        var count = UInt64(records.count), size = UInt64(bytes.count)
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &size) { data.append(contentsOf: $0) }
        records.withUnsafeBytes { data.append(contentsOf: $0) }
        data.append(contentsOf: bytes)
        try data.write(to: url, options: .atomic)
    }
    private var cache: [String: [InputCandidate]] = [:]
    private(set) var cachedCandidates = 0

    init(items: [Item], rankExactByWeight: Bool = false) {
        let sorted = items.sorted {
            if $0.code != $1.code { return $0.code < $1.code }
            if rankExactByWeight && $0.weight != $1.weight { return $0.weight > $1.weight }
            return $0.order < $1.order
        }
        bytes.reserveCapacity(items.reduce(0) { $0 + $1.text.utf8.count + $1.code.utf8.count })
        records.reserveCapacity(items.count)
        for item in sorted {
            let textStart = UInt32(bytes.count)
            bytes.append(contentsOf: item.text.utf8)
            let codeStart = UInt32(bytes.count)
            bytes.append(contentsOf: item.code.utf8)
            records.append(Record(textStart: textStart, textLength: codeStart - textStart,
                                  codeStart: codeStart, codeLength: UInt32(bytes.count) - codeStart,
                                  weight: item.weight))
        }
    }

    private func compare(_ record: Record, to key: [UInt8]) -> Int {
        let start = Int(record.codeStart)
        for offset in 0..<min(Int(record.codeLength), key.count) {
            let value = byte(start + offset)
            if value != key[offset] { return value < key[offset] ? -1 : 1 }
        }
        return Int(record.codeLength) == key.count ? 0 : (Int(record.codeLength) < key.count ? -1 : 1)
    }

    private func lowerBound(_ key: [UInt8]) -> Int {
        var low = 0
        var high = recordCount
        while low < high {
            let middle = (low + high) / 2
            if compare(record(middle), to: key) < 0 { low = middle + 1 }
            else { high = middle }
        }
        return low
    }

    private func text(_ record: Record) -> String {
        string(Int(record.textStart), Int(record.textLength))
    }

    func lookup(_ code: String) -> [String] {
        let key = Array(code.utf8)
        var position = lowerBound(key)
        var seen = Set<String>()
        var result: [String] = []
        while position < recordCount && compare(record(position), to: key) == 0 {
            let word = text(record(position))
            if seen.insert(word).inserted { result.append(word) }
            position += 1
        }
        return result
    }

    func candidates(prefix: String) -> [InputCandidate] {
        guard !prefix.isEmpty else { return [] }
        if let saved = cache[prefix] { return saved }
        let key = Array(prefix.utf8)
        var exact: [Int] = []
        var completions: [Int] = []
        var position = lowerBound(key)
        while position < recordCount {
            let record = record(position)
            let start = Int(record.codeStart)
            guard Int(record.codeLength) >= key.count,
                  key.indices.allSatisfy({ byte(start + $0) == key[$0] }) else { break }
            if Int(record.codeLength) == key.count { exact.append(position) }
            else { completions.append(position) }
            position += 1
        }
        completions.sort {
            let a = record($0), b = record($1)
            if a.weight != b.weight { return a.weight > b.weight }
            if a.codeLength != b.codeLength { return a.codeLength < b.codeLength }
            // Records are already ordered by code, then original candidate order.
            return $0 < $1
        }
        var seen = Set<String>()
        let result = (exact + completions).compactMap { index -> InputCandidate? in
            let record = record(index)
            let word = text(record)
            guard seen.insert(word).inserted else { return nil }
            let start = Int(record.codeStart) + key.count
            let end = Int(record.codeStart + record.codeLength)
            return InputCandidate(text: word, remainingCode: string(start, end - start))
        }
        // A one-letter prefix can return hundreds of thousands of words. Bound cache by entries.
        if result.count <= 4096 {
            if cache.count >= 32 || cachedCandidates + result.count > 4096 {
                cache.removeAll(keepingCapacity: true)
                cachedCandidates = 0
            }
            cache[prefix] = result
            cachedCandidates += result.count
        }
        return result
    }
}
