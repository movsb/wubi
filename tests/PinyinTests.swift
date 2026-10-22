import Foundation

func runPinyinTests() throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try """
    尼\tni\t10
    你\tni\t100
    你\tni\t100
    你好\tni hao\t100
    中国\tzhong guo\t100
    先\txian\t100
    西安\txi an\t50
    女\tnv\t50
    绿\tlv\t50
    错误\tbad!\t100
    """.write(to: temporary, atomically: true, encoding: .utf8)
    let dictionary = try PinyinDictionary(url: temporary)
    check(dictionary.count == 8, "Pinyin dictionary deduplicates and rejects invalid spelling")
    check(dictionary.lookup("ni") == ["你", "尼"], "Pinyin candidates sorted by weight")
    check(dictionary.lookup("nihao") == ["你好"], "concatenated multi-syllable Pinyin")
    check(dictionary.lookup("ni'hao") == ["你好"], "apostrophe-separated Pinyin")
    check(dictionary.lookup("zhongguo") == ["中国"], "Pinyin supports more than four letters")
    check(dictionary.lookup("xian") == ["先", "西安"], "ambiguous concatenation keeps weighted alternatives")
    check(dictionary.lookup("xi'an") == ["西安"], "explicit separator disambiguates syllables")
    check(dictionary.lookup("x'ian").isEmpty && dictionary.lookup("ni'").isEmpty, "invalid syllable boundary has no candidate")
    check(dictionary.lookup("nv") == ["女"] && dictionary.lookup("lv") == ["绿"], "v represents umlaut u")
    check(dictionary.lookup("Ni").isEmpty && dictionary.lookup("ni2").isEmpty && dictionary.lookup("").isEmpty,
          "non-Pinyin input does not accidentally match")

    var session = Session(pinyinLookup: dictionary.lookup)
    session.modifiers(code: 60, leftDown: false, rightDown: true)
    check(!session.engine.pinyinMode, "right Shift waits until release")
    session.modifiers(code: 60, leftDown: false)
    check(session.engine.pinyinMode && !session.engine.englishMode && session.modeHints == ["拼"], "right Shift enters Pinyin with hint")
    session.type("nihao")
    check(session.output.isEmpty && session.marked == "nihao" && session.engine.choices == ["你好"],
          "five-letter Pinyin stays marked and has Chinese candidate")
    session.key(" ", code: 49)
    check(session.output == "你好" && session.marked.isEmpty, "space commits Pinyin phrase")
    session.type("ni")
    session.key("2")
    check(session.output == "你好尼", "Pinyin numeric candidate selection")
    session.type("ni'hao")
    check(session.marked == "ni'hao" && session.engine.choices == ["你好"], "apostrophe is not converted to Chinese quote in Pinyin")
    session.key(" ", code: 49)
    check(session.output == "你好尼你好" && session.hints.isEmpty, "Pinyin delimiter produces no quote hint")
    session.type("zhongguo")
    session.key("\r", code: 36)
    check(session.output.hasSuffix("zhongguo"), "Return preserves raw Pinyin like Wubi")
    session.type("nihao")
    session.key("x")
    check(session.engine.choices.isEmpty && session.marked == "nihaox", "unknown Pinyin remains marked")
    session.key("\u{7f}", code: 51)
    check(session.engine.choices == ["你好"], "Backspace restores Pinyin candidates")
    session.key("\u{1b}", code: 53)
    check(session.marked.isEmpty && session.engine.pinyinMode, "Escape cancels Pinyin without changing mode")

    session.type("ni")
    session.tapRightShift()
    check(!session.engine.pinyinMode && !session.engine.englishMode && session.output.hasSuffix("ni"),
          "right Shift returns to Wubi and preserves unfinished raw text")
    session.type("q")
    session.key(" ", code: 49)
    check(session.output.hasSuffix("ni我"), "Wubi dictionary is restored after Pinyin")
    session.tapRightShift()
    session.tapLeftShift()
    check(session.engine.englishMode && session.engine.pinyinMode && session.modeHints.last == "英", "left Shift enters English from Pinyin")
    session.type("hello")
    check(session.output.hasSuffix("hello") && session.marked.isEmpty, "English remains direct input")
    session.tapLeftShift()
    check(!session.engine.englishMode && session.engine.pinyinMode && session.modeHints.last == "拼", "leaving English restores previous Pinyin mode")
    session.type("ni")
    session.key(";")
    check(session.output.hasSuffix("你；"), "Chinese punctuation works in Pinyin")
    session.tapLeftShift()
    session.tapRightShift()
    check(!session.engine.englishMode && session.engine.pinyinMode, "right Shift from English always enters Pinyin")

    session = Session(pinyinLookup: dictionary.lookup)
    session.modifiers(code: 60, leftDown: false, rightDown: true)
    session.key("A")
    session.modifiers(code: 60, leftDown: false)
    check(!session.engine.pinyinMode && !session.engine.englishMode, "right Shift uppercase chord does not toggle")
    session.key("\u{1b}", code: 53)
    session.modifiers(code: 60, leftDown: false, rightDown: true, shortcut: true)
    session.modifiers(code: 60, leftDown: false, shortcut: true)
    check(!session.engine.pinyinMode, "right Shift shortcut does not toggle")
    session.modifiers(code: 60, leftDown: false, rightDown: true)
    session.modifiers(leftDown: true, rightDown: true)
    session.modifiers(code: 60, leftDown: true)
    session.modifiers(leftDown: false)
    check(!session.engine.pinyinMode && !session.engine.englishMode, "both Shifts together do not toggle either mode")
    session.modifiers(code: 60, leftDown: false, rightDown: true)
    session.deactivate()
    session.modifiers(code: 60, leftDown: false)
    check(!session.engine.pinyinMode, "deactivation cancels pending right Shift tap")

    let realPath = "pinyin_simp.txt"
    if FileManager.default.fileExists(atPath: realPath) {
        let real = try PinyinDictionary(url: URL(fileURLWithPath: realPath))
        check(real.count > 60000, "full upstream Pinyin dictionary loads")
        check(real.lookup("nihao").contains("你好"), "upstream nihao")
        check(real.lookup("zhongguo").contains("中国"), "upstream zhongguo")
        check(real.lookup("xi'an").contains("西安"), "upstream explicit syllable boundary")
        check(real.lookup("nv").contains("女"), "upstream nv")
        print("PASS: upstream Pinyin dictionary; loaded \(real.count) entries")
    } else {
        print("SKIP: optional downloaded Pinyin dictionary; fixture tests still run")
    }
    print("PASS: Pinyin dictionary, right Shift and three-mode switching regressions")
}
