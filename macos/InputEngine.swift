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
}

struct InputResult {
    let handled: Bool
    var effects: [InputEffect] = []
}

struct InputEngine {
    private(set) var code = ""
    private(set) var page = 0
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
            page = 0
            return refresh()
        }
        if !code.isEmpty, choices.isEmpty, text.utf8.count == 1,
           let byte = text.utf8.first, (33...126).contains(byte) {
            code += text
            page = 0
            return refresh()
        }
        if !key.capsLock, let symbol = punctuation.convert(text) {
            var effects = commit()
            effects.append(insert(symbol))
            return InputResult(handled: true, effects: effects)
        }
        guard !code.isEmpty else { return InputResult(handled: false) }
        switch key.code {
        case 53:
            code = ""; page = 0
        case 51:
            code.removeLast(); page = 0
        case 36, 76:
            return InputResult(handled: true, effects: [insert(code)])
        case 49:
            return InputResult(handled: true, effects: commit())
        case 123, 126, 116:
            page = max(0, page - 1)
        case 124, 125, 121:
            page = min(max(0, (choices.count - 1) / 9), page + 1)
        default:
            if let digit = Int(text), (1...9).contains(digit) {
                let index = page * 9 + digit - 1
                if choices.indices.contains(index) {
                    return InputResult(handled: true, effects: [insert(choices[index])])
                }
                return InputResult(handled: true)
            } else if text == "-" || text == "=" {
                page = min(max(0, (choices.count - 1) / 9), max(0, page + (text == "=" ? 1 : -1)))
            } else {
                return InputResult(handled: false, effects: commit())
            }
        }
        return refresh()
    }

    mutating func commit() -> [InputEffect] {
        guard !code.isEmpty else { return [] }
        let values = choices
        return [insert(values.isEmpty ? code : values[min(page * 9, values.count - 1)])]
    }

    mutating func deactivate() -> [InputEffect] {
        let effects = commit()
        punctuation.reset()
        return effects
    }

    private func refresh() -> InputResult { InputResult(handled: true, effects: [.refresh]) }

    private mutating func insert(_ text: String) -> InputEffect {
        code = ""; page = 0
        return .insert(text)
    }
}
