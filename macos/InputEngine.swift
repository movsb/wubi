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
        let text = counts.keys.sorted().filter { validWord($0) && counts[$0]! > 0 }
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
    private var punctuation = ChinesePunctuation()
    private let usage: WordUsageStore?
    private let lookup: (String) -> [String]
    private let pinyinLookup: (String) -> [String]
    private let wubiCandidates: ((String) -> [InputCandidate])?
    private let pinyinCandidates: ((String) -> [InputCandidate])?

    init(lookup: @escaping (String) -> [String], pinyinLookup: @escaping (String) -> [String] = { _ in [] },
         wubiCandidates: ((String) -> [InputCandidate])? = nil,
         pinyinCandidates: ((String) -> [InputCandidate])? = nil,
         usage: WordUsageStore? = nil) {
        self.usage = usage
        self.lookup = lookup
        self.pinyinLookup = pinyinLookup
        self.wubiCandidates = wubiCandidates
        self.pinyinCandidates = pinyinCandidates
    }

    var choices: [String] { candidates.map(\.text) }

    var candidates: [InputCandidate] {
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

    mutating func handle(_ key: InputKey) -> InputResult {
        if key.isModifierChange { return handleModifiers(key) }
        shiftTapPending = false
        rightShiftTapPending = false
        // Let the client handle text and editing keys directly in English mode.
        if englishMode { return InputResult(handled: false) }
        if key.shortcut { return InputResult(handled: false, effects: commit()) }
        let text = key.text
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
        if !code.isEmpty, choices.isEmpty, text.utf8.count == 1,
           let byte = text.utf8.first, (33...126).contains(byte) {
            code += text
            selectedIndex = 0
            return refresh()
        }
        if !key.capsLock, !choices.isEmpty, [",", ".", "，", "。"].contains(text) {
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
            selectedIndex = min(max(0, choices.count - 1), selectedIndex + 1)
        default:
            if let digit = Int(text), (1...9).contains(digit) {
                let index = page * Self.pageSize + digit - 1
                if digit <= Self.pageSize && choices.indices.contains(index) {
                    return InputResult(handled: true, effects: [select(choices[index])])
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
        let values = choices
        guard !values.isEmpty else { return [insert(code)] }
        return [select(values[min(selectedIndex, values.count - 1)])]
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
        let target = min(max(0, (choices.count - 1) / Self.pageSize), max(0, requested))
        if target != page { selectedIndex = target * Self.pageSize }
    }

    private func refresh() -> InputResult { InputResult(handled: true, effects: [.refresh]) }

    private mutating func select(_ word: String) -> InputEffect {
        usage?.record(word)
        return insert(word)
    }

    private mutating func insert(_ text: String) -> InputEffect {
        code = ""; selectedIndex = 0
        return .insert(text)
    }
}
