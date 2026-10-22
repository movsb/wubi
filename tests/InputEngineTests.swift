import Foundation

struct Session {
    var engine: InputEngine
    var output = ""
    var marked = ""
    var hints: [String] = []
    var modeHints: [String] = []

    init(pinyinLookup: @escaping (String) -> [String] = { _ in [] },
         wubiCandidates: ((String) -> [InputCandidate])? = nil,
         pinyinCandidates: ((String) -> [InputCandidate])? = nil) {
        let words = ["q": ["我", "金"], "imde": ["没有"],
                     "a": (1...12).map { "候选\($0)" }]
        engine = InputEngine(lookup: { words[$0] ?? [] }, pinyinLookup: pinyinLookup,
                             wubiCandidates: wubiCandidates, pinyinCandidates: pinyinCandidates)
    }

    @discardableResult
    mutating func key(_ text: String = "", code: UInt16 = 0,
                      capsLock: Bool = false, shortcut: Bool = false) -> InputResult {
        let result = engine.handle(InputKey(text: text, code: code, capsLock: capsLock, shortcut: shortcut))
        apply(result.effects)
        // Like the client app, process events declined by the input method.
        if !result.handled && !shortcut {
            if code == 51 { if !output.isEmpty { output.removeLast() } }
            else if code == 36 || code == 76 { output += "\n" }
            else if code == 48 { output += "\t" }
            else if code == 0 || code == 49 { output += text }
        }
        return result
    }

    mutating func type(_ text: String) {
        for character in text { key(String(character)) }
    }

    mutating func apply(_ effects: [InputEffect]) {
        for effect in effects {
            switch effect {
            case .insert(let text): output += text; marked = ""
            case .refresh: marked = engine.code
            case .quoteHint(let text): hints.append(text)
            case .modeHint(let text): modeHints.append(text)
            }
        }
    }

    mutating func deactivate() {
        let effects = engine.deactivate()
        apply(effects)
    }

    mutating func modifiers(code: UInt16 = 56, leftDown: Bool, rightDown: Bool = false, shortcut: Bool = false, other: Bool = false) {
        let result = engine.handle(InputKey(code: code, shortcut: shortcut,
            isModifierChange: true, leftShiftDown: leftDown, rightShiftDown: rightDown, otherModifier: other))
        apply(result.effects)
    }

    mutating func tapLeftShift() {
        modifiers(leftDown: true)
        modifiers(leftDown: false)
    }

    mutating func tapRightShift() {
        modifiers(code: 60, leftDown: false, rightDown: true)
        modifiers(code: 60, leftDown: false)
    }
}

func runInputEngineTests() {
    var session = Session()
    session.type("imde")
    check(session.output.isEmpty && session.marked == "imde", "unique four-code candidate must not auto-commit")
    session.key(" ", code: 49)
    check(session.output == "没有" && session.marked.isEmpty, "Chinese space selects without extra space")

    session = Session()
    session.type("imde")
    session.key("x")
    check(session.output.isEmpty && session.marked == "imdex", "fifth letter stays in preedit instead of committing Chinese or English")
    check(session.engine.choices.isEmpty, "English preedit hides candidates")
    session.key(" ", code: 49)
    check(session.output == "imdex" && session.marked.isEmpty, "space commits whole English word without trailing space")

    session = Session()
    session.type("hello")
    check(session.output.isEmpty && session.marked == "hello", "unknown prefixes continue accumulating")
    session.key("\r", code: 36)
    check(session.output == "hello" && session.marked.isEmpty, "Return commits English without newline")
    session.type("q")
    session.key(" ", code: 49)
    session.type("world")
    session.key(" ", code: 49)
    check(session.output == "hello我world", "English-Chinese-English mixed input")

    session = Session()
    session.type("xyz")
    check(session.marked == "xyz" && session.output.isEmpty, "unknown sequences below four letters remain marked")
    session.key(" ", code: 49)
    check(session.output == "xyz", "short unknown sequence commits raw")

    session = Session()
    session.type("OpenAI2026's-test")
    check(session.marked == "OpenAI2026's-test" && session.output.isEmpty, "mixed-case alphanumeric English word remains marked")
    session.key("\r", code: 76)
    check(session.output == "OpenAI2026's-test", "keypad Enter commits raw English")

    session = Session()
    session.type("imdex")
    session.key("\u{7f}", code: 51)
    check(session.marked == "imde" && session.engine.choices == ["没有"], "Backspace restores Chinese candidates")
    session.key(" ", code: 49)
    check(session.output == "没有", "restored candidate can be selected")

    session = Session()
    session.type("hello")
    session.key("\u{1b}", code: 53)
    check(session.marked.isEmpty && session.output.isEmpty && session.engine.code.isEmpty, "Escape cancels English without committing")
    session.type("q")
    session.key("\u{7f}", code: 51)
    check(session.marked.isEmpty && session.engine.choices.isEmpty, "Backspace to empty clears preedit")
    check(!session.key("\u{7f}", code: 51).handled, "Backspace with empty preedit passes through")

    session = Session()
    session.type("q")
    session.key("2")
    check(session.output == "金", "numeric candidate selection")
    session.type("q")
    session.key("9")
    check(session.marked == "q" && session.output == "金", "invalid candidate number leaves preedit intact")
    session.key("\r", code: 36)
    check(session.output == "金q", "Return preserves raw text even for valid Chinese code")

    session = Session()
    session.type("a")
    session.key(".")
    check(session.engine.page == 1, "next page")
    session.key(".")
    check(session.engine.page == 2, "third page contains remaining candidates")
    session.key(".")
    check(session.engine.page == 2, "last page is clamped")
    session.key("2")
    check(session.output == "候选12" && session.engine.page == 0, "number selects from current page and resets page")
    session.type("a")
    session.key(".")
    session.key(" ", code: 49)
    check(session.output == "候选12候选6", "space selects first candidate on current page")
    session.type("a")
    session.key(",")
    check(session.engine.page == 0, "first page is clamped")
    session.key("", code: 125)
    session.key("", code: 126)
    check(session.engine.page == 0, "Down and Up restore original selection")
    session.key(".")
    session.type("b")
    check(session.engine.page == 0 && session.marked == "ab", "typing resets candidate page")

    session = Session()
    session.type("q")
    session.key(";")
    check(session.output == "我；" && session.marked.isEmpty, "punctuation commits candidate then Chinese punctuation")
    session.key("\"")
    session.type("q")
    session.key(" ", code: 49)
    session.key("\"")
    check(session.output == "我；“我”", "quote pairs survive normal commits")
    session.key(".", capsLock: true)
    check(session.output == "我；“我”.", "Caps Lock punctuation stays ASCII")

    session = Session()
    session.type("q")
    let shortcut = session.key("c", shortcut: true)
    check(!shortcut.handled && session.output == "我" && session.marked.isEmpty, "shortcuts commit composition then pass through")
    session.type("hello")
    session.deactivate()
    check(session.output == "我hello" && session.marked.isEmpty, "deactivation commits English once")
    session.deactivate()
    check(session.output == "我hello", "repeated commit is idempotent")
    session.key("\"")
    session.deactivate()
    session.key("\"")
    check(session.output.hasSuffix("““"), "deactivation resets quote pairing")

    session = Session()
    check(!session.key(" ", code: 49).handled && session.output == " ", "space with empty preedit passes through")
    check(!session.key("\r", code: 36).handled && session.output == " \n", "Return with empty preedit passes through")
    session.key("A", capsLock: true)
    check(session.marked.isEmpty && session.output == " \nA", "Caps Lock text bypasses composition")
    session.type("q")
    session.key("\t", code: 48)
    check(session.output == " \nA我\t", "Tab commits candidate and passes through")
    session = Session()
    session.type("a")
    session.key("", code: 126)
    check(session.engine.selectedIndex == 0, "Up at first candidate is clamped")
    session.key("", code: 125)
    check(session.engine.selectedIndex == 1 && session.engine.page == 0 && session.output.isEmpty,
          "Down selects candidate 2 instead of paging")
    session.key("", code: 125)
    check(session.engine.selectedIndex == 2 && session.engine.page == 0, "Down selects candidate 3")
    session.key("", code: 126)
    check(session.engine.selectedIndex == 1, "Up moves selection back one candidate")
    session.key(" ", code: 49)
    check(session.output == "候选2", "space commits arrow-selected candidate")

    session = Session()
    session.type("a")
    for _ in 0..<5 { session.key("", code: 125) }
    check(session.engine.selectedIndex == 5 && session.engine.page == 1, "Down crosses page after candidate 5")
    session.key("", code: 126)
    check(session.engine.selectedIndex == 4 && session.engine.page == 0, "Up crosses back to candidate 5")
    for _ in 0..<10 { session.key("", code: 125) }
    check(session.engine.selectedIndex == 11, "Down clamps at final candidate")
    session.key(" ", code: 49)
    check(session.output == "候选12", "space commits last selected candidate")

    session = Session()
    session.type("a")
    session.key(".")
    check(session.engine.page == 1 && session.marked == "a" && session.output.isEmpty,
          "period pages instead of inserting punctuation")
    session.key(",")
    check(session.engine.page == 0 && session.marked == "a", "comma goes to previous page")
    session.key(",")
    check(session.engine.page == 0 && session.output.isEmpty, "comma at first page does not insert punctuation")
    session.key("。")
    check(session.engine.page == 1, "Chinese period also pages")
    session.key("，")
    check(session.engine.page == 0, "Chinese comma also pages")
    session.key(".")
    session.key(" ", code: 49)
    check(session.output == "候选6", "space selects first candidate on destination page")
    session.type("a")
    session.key(".")
    session.key("3")
    check(session.output == "候选6候选8", "numbers select from destination page")

    session = Session()
    session.type("a")
    for digit in ["6", "7", "8", "9"] { session.key(digit) }
    check(session.output.isEmpty && session.marked == "a", "numbers beyond five do not select invisible candidates")
    session.key("5")
    check(session.output == "候选5", "number five selects final visible candidate")
    session.type("a")
    session.key(".")
    session.key("6")
    check(session.output == "候选5" && session.marked == "a", "number six cannot select a candidate on next page")
    session.key(".")
    check(session.engine.page == 2 && session.engine.selectedIndex == 10, "third page starts at candidate eleven")
    session.key("3")
    check(session.output == "候选5" && session.marked == "a", "missing candidate on partial final page does not commit")
    session.key("2")
    check(session.output == "候选5候选12", "partial final page candidate selection")

    for removed in [InputKey(code: 123), InputKey(code: 124), InputKey(code: 116),
                    InputKey(code: 121), InputKey(text: "-"), InputKey(text: "=")] {
        var removedSession = Session()
        removedSession.type("a")
        let result = removedSession.key(removed.text, code: removed.code)
        check(!result.handled && removedSession.engine.page == 0,
              "removed paging key passes through: \(removed)")
    }

    session = Session()
    session.type("a")
    session.key(".")
    session.type("b")
    check(session.engine.page == 0 && session.engine.choices.isEmpty, "new input resets candidate page")
    session.key("\u{7f}", code: 51)
    check(session.engine.page == 0 && session.engine.choices.count == 12, "Backspace restores candidates on first page")
    session.key(".")
    session.key("\u{1b}", code: 53)
    check(session.engine.selectedIndex == 0 && session.marked.isEmpty, "Escape resets paging")
    session.type("hello")
    session.key(",")
    session.key(".")
    session.key("", code: 125)
    session.key("", code: 126)
    check(session.marked == "hello,." && session.engine.page == 0 && session.output.isEmpty,
          "paging keys preserve English preedit without candidates")
    session = Session()
    session.key(",")
    session.key(".")
    check(session.output == "，。", "comma and period without preedit insert Chinese punctuation")
    check(!session.key("", code: 125).handled && !session.key("", code: 126).handled,
          "Up/Down with empty preedit pass through")
    session.type("a")
    session.key("<")
    check(session.output == "，。候选1《", "Shift-comma still inserts book-title punctuation")

    session = Session()
    session.key("\"")
    check(session.output == "“" && session.hints == ["左"], "opening double quote emits matching hint")
    session.key("\"")
    check(session.output == "“”" && session.hints.last == "右", "closing double quote emits matching hint")
    session.key("'")
    check(session.hints.last == "左", "opening single quote hint")
    session.key("'")
    check(session.hints.last == "右" && session.hints.count == 4, "closing single quote hint")
    session.key(",")
    check(session.hints.count == 4, "ordinary punctuation has no quote hint")
    session.key("\"", capsLock: true)
    check(session.hints.count == 4 && session.output.hasSuffix("\""), "ASCII quote has no Chinese quote hint")
    session.type("hello")
    session.key("'")
    check(session.marked == "hello'" && session.hints.count == 4, "English apostrophe in preedit has no quote hint")

    session = Session()
    session.type("q")
    let quote = session.key("\"")
    check(quote.effects == [.insert("我"), .insert("“"), .quoteHint("左")],
          "hint follows Chinese candidate and actual quote insertion")
    check(session.output == "我“" && session.marked.isEmpty, "hint never inserts explanatory text into document")
    session = Session()
    session.modifiers(leftDown: true)
    check(!session.engine.englishMode, "Shift down alone waits for release")
    session.modifiers(leftDown: false)
    check(session.engine.englishMode && session.modeHints == ["英"], "left Shift tap enables English with hint")
    let direct = session.key("q")
    check(!direct.handled && direct.effects.isEmpty && session.output == "q" && session.marked.isEmpty,
          "English letters go directly to client without preedit")
    session.type("Hello123,.'\"")
    check(session.output == "qHello123,.'\"" && session.hints.isEmpty && session.marked.isEmpty,
          "English mode preserves letters digits punctuation and quotes")
    session.key(" ", code: 49)
    session.key("\r", code: 36)
    check(session.output.hasSuffix(" \n"), "English space and Return pass directly to client")
    check(!session.key("", code: 125).handled, "English navigation is not intercepted")
    let englishShortcut = session.key("c", shortcut: true)
    check(!englishShortcut.handled && englishShortcut.effects.isEmpty, "English shortcuts pass through")
    session.tapLeftShift()
    check(!session.engine.englishMode && session.modeHints == ["英", "五"], "second left Shift tap restores Chinese")
    session.type("q")
    session.key(" ", code: 49)
    check(session.output.hasSuffix("我") && session.marked.isEmpty, "Chinese composition works after switching back")

    session = Session()
    session.type("q")
    session.tapLeftShift()
    check(session.output == "q" && session.marked.isEmpty && session.engine.englishMode,
          "switching to English preserves unfinished raw text instead of choosing Chinese")
    session.key("\u{7f}", code: 51)
    check(session.output.isEmpty && session.marked.isEmpty, "English Backspace edits client directly")
    session.deactivate()
    check(session.engine.englishMode, "deactivation does not reset language preference")

    session = Session()
    session.modifiers(leftDown: true)
    session.key("A")
    session.modifiers(leftDown: false)
    check(!session.engine.englishMode && session.marked == "A" && session.modeHints.isEmpty,
          "Shift-letter chord does not toggle mode")
    session.key("\u{1b}", code: 53)
    session.modifiers(leftDown: true)
    session.key("?")
    session.modifiers(leftDown: false)
    check(!session.engine.englishMode && session.output == "？", "Shift-symbol chord does not toggle mode")
    session.tapRightShift()
    check(session.engine.pinyinMode && !session.engine.englishMode, "right Shift switches Pinyin without enabling English")
    session.tapRightShift()
    check(!session.engine.pinyinMode, "second right Shift restores Wubi")
    session.modifiers(leftDown: true, shortcut: true)
    session.modifiers(leftDown: false, shortcut: true)
    check(!session.engine.englishMode, "Command-Control-Option with Shift does not toggle")
    session.modifiers(leftDown: true)
    session.modifiers(code: 55, leftDown: true, shortcut: true)
    session.modifiers(code: 55, leftDown: true)
    session.modifiers(leftDown: false)
    check(!session.engine.englishMode, "another modifier pressed during Shift cancels tap")
    session.modifiers(leftDown: true)
    session.modifiers(code: 60, leftDown: true, other: true)
    session.modifiers(leftDown: false, other: true)
    session.modifiers(code: 60, leftDown: false)
    check(!session.engine.englishMode, "holding both Shift keys does not toggle")
    session.modifiers(leftDown: true)
    session.deactivate()
    session.modifiers(leftDown: false)
    check(!session.engine.englishMode, "deactivation cancels a pending Shift tap")
    session.tapLeftShift()
    check(session.engine.englishMode, "Shift tap still works after interrupted tap")
    session.modifiers(leftDown: true)
    session.key("B")
    session.modifiers(leftDown: false)
    check(session.engine.englishMode && session.output.hasSuffix("B") && session.marked.isEmpty,
          "Shift-uppercase in English remains direct English input")
    print("PASS: preedit, mixed input, selection, punctuation, quote hints and Shift mode regressions")
}
