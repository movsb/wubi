// Input behavior lives here so regression tests exercise the same code as InputMethodKit.
struct InputKey {
    var text: String = ""
    var code: UInt16 = 0
    var capsLock = false
    var shortcut = false
}

enum InputEffect: Equatable {
    case insert(String)
    case refresh
    case quoteHint(String)
}

struct InputResult {
    let handled: Bool
    var effects: [InputEffect] = []
}

struct InputEngine {
    private(set) var code = ""
    private(set) var selectedIndex = 0
    var page: Int { selectedIndex / 9 }
    private var punctuation = ChinesePunctuation()
    private let lookup: (String) -> [String]

    init(lookup: @escaping (String) -> [String]) { self.lookup = lookup }

    var choices: [String] {
        guard code.utf8.allSatisfy({ (97...122).contains($0) }) else { return [] }
        return lookup(code)
    }

    mutating func handle(_ key: InputKey) -> InputResult {
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
        case 123, 116:
            selectPage(page - 1)
        case 124, 121:
            selectPage(page + 1)
        default:
            if let digit = Int(text), (1...9).contains(digit) {
                let index = page * 9 + digit - 1
                if choices.indices.contains(index) {
                    return InputResult(handled: true, effects: [insert(choices[index])])
                }
                return InputResult(handled: true)
            } else if text == "-" || text == "=" {
                selectPage(page + (text == "=" ? 1 : -1))
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
        return effects
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
