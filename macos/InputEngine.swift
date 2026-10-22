// Input behavior lives here so regression tests exercise the same code as InputMethodKit.
struct InputKey {
    var text: String = ""
    var code: UInt16 = 0
    var capsLock = false
    var shortcut = false
    var isModifierChange = false
    var leftShiftDown = false
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
    private(set) var code = ""
    private(set) var selectedIndex = 0
    private(set) var englishMode = false
    private var leftShiftPressed = false
    private var shiftTapPending = false
    var page: Int { selectedIndex / 9 }
    private var punctuation = ChinesePunctuation()
    private let lookup: (String) -> [String]

    init(lookup: @escaping (String) -> [String]) { self.lookup = lookup }

    var choices: [String] {
        guard code.utf8.allSatisfy({ (97...122).contains($0) }) else { return [] }
        return lookup(code)
    }

    mutating func handle(_ key: InputKey) -> InputResult {
        if key.isModifierChange { return handleModifiers(key) }
        shiftTapPending = false
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
                let index = page * 9 + digit - 1
                if choices.indices.contains(index) {
                    return InputResult(handled: true, effects: [insert(choices[index])])
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
        return [insert(values.isEmpty ? code : values[min(selectedIndex, values.count - 1)])]
    }

    mutating func deactivate() -> [InputEffect] {
        let effects = commit()
        punctuation.reset()
        leftShiftPressed = false
        shiftTapPending = false
        return effects
    }

    private mutating func handleModifiers(_ key: InputKey) -> InputResult {
        guard key.code == 56 else {
            shiftTapPending = false
            return InputResult(handled: false)
        }
        let wasPressed = leftShiftPressed
        leftShiftPressed = key.leftShiftDown
        if key.leftShiftDown && !wasPressed {
            shiftTapPending = !key.shortcut && !key.otherModifier
        } else if !key.leftShiftDown && wasPressed {
            let shouldToggle = shiftTapPending && !key.shortcut && !key.otherModifier
            shiftTapPending = false
            if shouldToggle {
                var effects: [InputEffect] = []
                // Preserve an unfinished word as typed when explicitly switching to English.
                if !code.isEmpty { effects.append(insert(code)) }
                englishMode.toggle()
                punctuation.reset()
                effects.append(.modeHint(englishMode ? "英" : "中"))
                return InputResult(handled: true, effects: effects)
            }
        }
        return InputResult(handled: false)
    }

    private mutating func selectPage(_ requested: Int) {
        let target = min(max(0, (choices.count - 1) / 9), max(0, requested))
        if target != page { selectedIndex = target * 9 }
    }

    private func refresh() -> InputResult { InputResult(handled: true, effects: [.refresh]) }

    private mutating func insert(_ text: String) -> InputEffect {
        code = ""; selectedIndex = 0
        return .insert(text)
    }
}
