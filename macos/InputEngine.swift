import Foundation

// Shared across input clients, modes and codes. Only confirmed dictionary words are learned.
final class WordUsageStore {
    static let shared = WordUsageStore(url: FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Wubi/frequencies.txt"))
    private let url: URL
    private let saveDelay: TimeInterval
    private var saveTimer: Timer?
    private let saveQueue = DispatchQueue(label: "Wubi.word-usage-save", qos: .utility)
    private(set) var counts: [String: Int]

    init(url: URL, saveDelay: TimeInterval = 10 * 60) {
        self.saveDelay = saveDelay
        self.url = url
        counts = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                for line in text.split(whereSeparator: \.isNewline) {
                    let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                    guard fields.count == 2, !fields[0].isEmpty,
                          let count = Int(fields[1]), count > 0 else { continue }
                    let word = String(fields[0])
                    counts[word] = max(counts[word] ?? 0, count)
                }
            }
        }
    }

    func record(_ word: String) {
        let count = counts[word] ?? 0
        counts[word] = count == Int.max ? count : count + 1
        saveTimer?.invalidate()
        let timer = Timer(timeInterval: saveDelay, repeats: false) { [weak self] _ in
            self?.saveAfterIdle()
        }
        saveTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    deinit { saveTimer?.invalidate() }

    private func saveAfterIdle() {
        saveTimer = nil
        let snapshot = counts
        let destination = url
        saveQueue.async {
            do {
                try Self.write(snapshot, to: destination)
            } catch {
                NSLog("保存个人词频失败：%@", error.localizedDescription)
            }
        }
    }

    private static func validWord(_ word: String) -> Bool {
        !word.isEmpty && word.rangeOfCharacter(from: .newlines.union(CharacterSet(charactersIn: "\t"))) == nil
    }

    private static func write(_ counts: [String: Int], to url: URL) throws {
        let excluded = try DictionaryRow.readExcludedWords(url.deletingLastPathComponent().appendingPathComponent("excluded.txt"))
        let text = counts.keys.sorted().filter { validWord($0) && counts[$0]! > 0 && !excluded.contains($0) }
            .map { $0 + "\t" + String(counts[$0]!) + "\n" }.joined()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func rank(_ candidates: [InputCandidate]) -> [InputCandidate] {
        candidates.enumerated().sorted {
            let leftExact = $0.element.remainingCode.isEmpty
            let rightExact = $1.element.remainingCode.isEmpty
            if leftExact != rightExact { return leftExact }
            let left = counts[$0.element.text] ?? 0
            let right = counts[$1.element.text] ?? 0
            return left == right ? $0.offset < $1.offset : left > right
        }.map(\.element)
    }
}

// Input behavior lives here so regression tests exercise the same code as InputMethodKit.
struct InputKey {
    var text: String = ""
    var code: UInt16 = 0
    var capsLock = false
    var shortcut = false
    var isModifierChange = false
    var leftShiftDown = false
    var rightShiftDown = false
    var otherModifier = false
}

enum InputEffect: Equatable {
    case insert(String)
    case refresh
    case queryExternal(String, UUID)
    case savePhrase(String, String)
    case quoteHint(String)
    case modeHint(String)
}

struct InputResult {
    let handled: Bool
    var effects: [InputEffect] = []
}

struct InputEngine {
    static let pageSize = 5
    private(set) var code = ""
    private(set) var selectedIndex = 0
    private(set) var englishMode = false
    private(set) var pinyinMode = false
    private var leftShiftPressed = false
    private var rightShiftPressed = false
    private var rightShiftTapPending = false
    private var shiftTapPending = false
    var page: Int { selectedIndex / Self.pageSize }
    private(set) var externalRequest: UUID?
    private var externalCandidates: ExternalCandidates?
    private var phraseWord: String?
    private var phraseReadings: ManualReadings?
    private let readings: (Character) -> [String]
    var collectingPhrase: Bool { externalRequest != nil || externalCandidates != nil || phraseWord != nil }
    private mutating func cancelCollection() {
        externalRequest = nil; externalCandidates = nil; phraseWord = nil; phraseReadings = nil
        selectedIndex = 0
    }
    mutating func receiveExternal(_ words: [String], request: UUID, readings: [String: [String]] = [:]) -> Bool {
        receiveExternal(ExternalCandidates(words: words, readings: readings), request: request)
    }
    mutating func receiveExternal(_ candidates: ExternalCandidates, request: UUID) -> Bool {
        guard externalRequest == request else { return false }
        externalRequest = nil
        externalCandidates = candidates
        selectedIndex = 0
        return true
    }
    private var punctuation = ChinesePunctuation()
    private let usage: WordUsageStore?
    private let lookup: (String) -> [String]
    private let pinyinLookup: (String) -> [String]
    private let wubiCandidates: ((String) -> [InputCandidate])?
    private let pinyinCandidates: ((String) -> [InputCandidate])?

    init(lookup: @escaping (String) -> [String], pinyinLookup: @escaping (String) -> [String] = { _ in [] },
         wubiCandidates: ((String) -> [InputCandidate])? = nil,
         pinyinCandidates: ((String) -> [InputCandidate])? = nil,
         readings: @escaping (Character) -> [String] = { _ in [] },
         usage: WordUsageStore? = nil) {
        self.readings = readings
        self.usage = usage
        self.lookup = lookup
        self.pinyinLookup = pinyinLookup
        self.wubiCandidates = wubiCandidates
        self.pinyinCandidates = pinyinCandidates
    }

    // Full arrays are kept for callers inspecting ordinary dictionary results.
    // Input handling and rendering use count, indexed access and the visible page.
    var choices: [String] { candidates.map(\.text) }
    var candidates: [InputCandidate] {
        if collectingPhrase { return (0..<candidateCount).compactMap { candidate(at: $0) } }
        return ordinaryCandidates
    }
    var candidateCount: Int {
        guard !englishMode else { return 0 }
        if let options = phraseReadings { return options.count }
        if let external = externalCandidates { return external.count }
        if externalRequest != nil { return 0 }
        return ordinaryCandidates.count
    }
    func candidate(at index: Int) -> InputCandidate? {
        guard !englishMode, index >= 0 else { return nil }
        if let options = phraseReadings {
            return options.spelling(at: index).map { InputCandidate(text: $0, remainingCode: "") }
        }
        if let external = externalCandidates {
            return external.word(at: index).map { InputCandidate(text: $0, remainingCode: "") }
        }
        if externalRequest != nil { return nil }
        let values = ordinaryCandidates
        return values.indices.contains(index) ? values[index] : nil
    }
    var visibleCandidates: [InputCandidate] {
        let start = page * Self.pageSize
        if collectingPhrase {
            let end = start + min(Self.pageSize, max(0, candidateCount - start))
            return (start..<end).compactMap { candidate(at: $0) }
        }
        return Array(ordinaryCandidates.dropFirst(start).prefix(Self.pageSize))
    }
    private var ordinaryCandidates: [InputCandidate] {
        guard !englishMode else { return [] }
        if pinyinMode {
            guard code.utf8.allSatisfy({ (97...122).contains($0) || $0 == 39 }) else { return [] }
            let values = pinyinCandidates?(code) ?? pinyinLookup(code).map { InputCandidate(text: $0, remainingCode: "") }
            return usage?.rank(values) ?? values
        }
        guard code.utf8.allSatisfy({ (97...122).contains($0) }) else { return [] }
        let values = wubiCandidates?(code) ?? lookup(code).map { InputCandidate(text: $0, remainingCode: "") }
        // Short Wubi codes are fixed muscle memory, even after learning in another mode.
        guard code.count == 4 else { return values }
        return usage?.rank(values) ?? values
    }

    mutating func refreshCandidates() {
        selectedIndex = min(selectedIndex, max(0, candidateCount - 1))
    }

    mutating func handle(_ key: InputKey) -> InputResult {
        if key.isModifierChange { return handleModifiers(key) }
        shiftTapPending = false
        rightShiftTapPending = false
        // Let the client handle text and editing keys directly in English mode.
        if englishMode { return InputResult(handled: false) }
        if key.shortcut { return InputResult(handled: false, effects: commit()) }
        let text = key.text
        if !key.capsLock, !pinyinMode, (1...4).contains(code.count), text == "*",
           code.utf8.allSatisfy({ (97...122).contains($0) }) {
            cancelCollection()
            let request = UUID()
            externalRequest = request
            return InputResult(handled: true, effects: [.refresh, .queryExternal(code, request)])
        }
        if collectingPhrase {
            if key.code == 53 || key.code == 51 {
                cancelCollection()
                return refresh()
            }
            if key.code == 49 || (Int(text).map { (1...5).contains($0) } ?? false) {
                let index = key.code == 49 ? selectedIndex : page * Self.pageSize + Int(text)! - 1
                guard let selected = candidate(at: index)?.text else { return refresh() }
                if let word = phraseWord {
                    return InputResult(handled: true, effects: [.savePhrase(word, selected)])
                }
                let word = selected
                do {
                    let baseReadings = readings
                    let extra = externalCandidates
                    phraseReadings = try ManualReadings(word: word) { character in
                        let base = baseReadings(character)
                        return base + (extra?.readings(for: character) ?? []).filter { !base.contains($0) }
                    }
                    phraseWord = word
                    externalCandidates = nil
                    selectedIndex = 0
                    return refresh()
                } catch {
                    return InputResult(handled: true, effects: [.modeHint(error.localizedDescription)])
                }
            }
            if ![",", ".", "，", "。"].contains(text), key.code != 125, key.code != 126 {
                // Other keys return to ordinary input without accepting an unconfirmed phrase.
                cancelCollection()
            }
        }
        if text.utf8.count == 1, let byte = text.utf8.first,
           (97...122).contains(byte) || (65...90).contains(byte), !key.capsLock {
            code += text
            selectedIndex = 0
            return refresh()
        }
        if pinyinMode, !code.isEmpty, text == "'", !key.capsLock {
            code += text
            selectedIndex = 0
            return refresh()
        }
        if !collectingPhrase, !code.isEmpty, candidateCount == 0, text.utf8.count == 1,
           let byte = text.utf8.first, (33...126).contains(byte) {
            code += text
            selectedIndex = 0
            return refresh()
        }
        if !key.capsLock, candidateCount > 0, [",", ".", "，", "。"].contains(text) {
            selectPage(page + ((text == "," || text == "，") ? -1 : 1))
            return refresh()
        }
        if !key.capsLock, let symbol = punctuation.convert(text) {
            var effects = commit()
            effects.append(insert(symbol))
            if let hint = ChinesePunctuation.quoteHint(for: symbol) {
                effects.append(.quoteHint(hint))
            }
            return InputResult(handled: true, effects: effects)
        }
        guard !code.isEmpty else { return InputResult(handled: false) }
        switch key.code {
        case 53:
            code = ""; selectedIndex = 0
        case 51:
            code.removeLast(); selectedIndex = 0
        case 36, 76:
            return InputResult(handled: true, effects: [insert(code)])
        case 49:
            return InputResult(handled: true, effects: commit())
        case 126:
            selectedIndex = max(0, selectedIndex - 1)
        case 125:
            selectedIndex = min(max(0, candidateCount - 1), selectedIndex + 1)
        default:
            if let digit = Int(text), (1...9).contains(digit) {
                let index = page * Self.pageSize + digit - 1
                if digit <= Self.pageSize, let selected = candidate(at: index)?.text {
                    return InputResult(handled: true, effects: [select(selected)])
                }
                return InputResult(handled: true)
            } else {
                return InputResult(handled: false, effects: commit())
            }
        }
        return refresh()
    }

    mutating func commit() -> [InputEffect] {
        guard !code.isEmpty else { return [] }
        if collectingPhrase { cancelCollection(); return [insert(code)] }
        guard let selected = candidate(at: min(selectedIndex, max(0, candidateCount - 1)))?.text else { return [insert(code)] }
        return [select(selected)]
    }

    mutating func finishPhrase(_ word: String) -> [InputEffect] {
        usage?.record(word)
        return [insert(word)]
    }

    mutating func deactivate() -> [InputEffect] {
        let effects = commit()
        punctuation.reset()
        leftShiftPressed = false
        rightShiftPressed = false
        shiftTapPending = false
        rightShiftTapPending = false
        return effects
    }

    private mutating func handleModifiers(_ key: InputKey) -> InputResult {
        if key.code == 60 {
            shiftTapPending = false
            let wasPressed = rightShiftPressed
            rightShiftPressed = key.rightShiftDown
            if key.rightShiftDown && !wasPressed {
                rightShiftTapPending = !key.shortcut && !key.otherModifier && !key.leftShiftDown
            } else if !key.rightShiftDown && wasPressed {
                let shouldToggle = rightShiftTapPending && !key.shortcut && !key.otherModifier && !key.leftShiftDown
                rightShiftTapPending = false
                if shouldToggle {
                    var effects: [InputEffect] = []
                    if !code.isEmpty { effects.append(insert(code)) }
                    pinyinMode = englishMode || !pinyinMode
                    englishMode = false
                    punctuation.reset()
                    effects.append(.modeHint(pinyinMode ? "拼" : "五"))
                    return InputResult(handled: true, effects: effects)
                }
            }
            return InputResult(handled: false)
        }
        rightShiftTapPending = false
        guard key.code == 56 else {
            shiftTapPending = false
            return InputResult(handled: false)
        }
        let wasPressed = leftShiftPressed
        leftShiftPressed = key.leftShiftDown
        if key.leftShiftDown && !wasPressed {
            shiftTapPending = !key.shortcut && !key.otherModifier && !key.rightShiftDown
        } else if !key.leftShiftDown && wasPressed {
            let shouldToggle = shiftTapPending && !key.shortcut && !key.otherModifier && !key.rightShiftDown
            shiftTapPending = false
            if shouldToggle {
                var effects: [InputEffect] = []
                // Preserve an unfinished word as typed when explicitly switching to English.
                if !code.isEmpty { effects.append(insert(code)) }
                englishMode.toggle()
                punctuation.reset()
                effects.append(.modeHint(englishMode ? "英" : (pinyinMode ? "拼" : "五")))
                return InputResult(handled: true, effects: effects)
            }
        }
        return InputResult(handled: false)
    }

    private mutating func selectPage(_ requested: Int) {
        let target = min(max(0, (candidateCount - 1) / Self.pageSize), max(0, requested))
        if target != page { selectedIndex = target * Self.pageSize }
    }

    private func refresh() -> InputResult { InputResult(handled: true, effects: [.refresh]) }

    private mutating func select(_ word: String) -> InputEffect {
        usage?.record(word)
        return insert(word)
    }

    private mutating func insert(_ text: String) -> InputEffect {
        cancelCollection()
        code = ""; selectedIndex = 0
        return .insert(text)
    }
}
