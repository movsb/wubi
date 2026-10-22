import Foundation

func runPrefixTests() throws {
    let wubiRows = [
        DictionaryRow(word: "短码词", code: "im", weight: 1),
        DictionaryRow(word: "没有", code: "imde", weight: 100),
        DictionaryRow(word: "尚有", code: "imde", weight: 20),
        DictionaryRow(word: "别词", code: "imdf", weight: 50),
        DictionaryRow(word: "末词", code: "imdg", weight: 40),
        DictionaryRow(word: "备选", code: "imdh", weight: 30),
        DictionaryRow(word: "其他", code: "imdi", weight: 10),
        DictionaryRow(word: "重复词", code: "imdj", weight: 5),
        DictionaryRow(word: "重复词", code: "imdk", weight: 6),
    ]
    let wubi = WubiDictionary(rows: wubiRows)
    let partial = wubi.candidates(prefix: "im")
    check(partial.first == InputCandidate(text: "短码词", remainingCode: ""), "exact Wubi match precedes higher-frequency completions")
    check(partial[1] == InputCandidate(text: "没有", remainingCode: "de"), "Wubi completion displays remaining code")
    check(partial.map(\.text) == ["短码词", "没有", "别词", "末词", "备选", "尚有", "其他", "重复词"], "completion frequency order and duplicate-word removal")
    check(wubi.lookup("imd").isEmpty && wubi.candidates(prefix: "imd").first == .init(text: "没有", remainingCode: "e"),
          "prefix without an exact match still returns candidates")
    check(wubi.candidates(prefix: "imde") == [.init(text: "没有", remainingCode: ""), .init(text: "尚有", remainingCode: "")],
          "full Wubi code preserves exact candidate order without suffixes")
    check(wubi.candidates(prefix: "").isEmpty && wubi.candidates(prefix: "imdez").isEmpty,
          "empty and overlong Wubi input have no candidates")
    check(wubi.candidates(prefix: "IM").isEmpty && wubi.candidates(prefix: "im1").isEmpty, "uppercase and English digits do not match Wubi prefixes")
    check(wubi.candidates(prefix: "im") == partial, "cached query preserves ranking and suffixes")
    for code in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "aa", "ab", "ac", "ad", "ae", "af", "ag"] {
        _ = wubi.candidates(prefix: code)
    }
    check(wubi.candidates(prefix: "im") == partial, "cache eviction does not change results")
    let duplicate = WubiDictionary(rows: [
        .init(word: "没有", code: "im", weight: 1), .init(word: "没有", code: "imde", weight: 1000),
    ])
    check(duplicate.candidates(prefix: "im") == [.init(text: "没有", remainingCode: "")], "exact word suppresses its duplicate completion")

    let pinyin = PinyinDictionary(rows: [
        .init(word: "你", code: "ni", weight: 20), .init(word: "泥", code: "ni", weight: 10),
        .init(word: "你好", code: "ni hao", weight: 100), .init(word: "你好啊", code: "ni hao a", weight: 50),
        .init(word: "中国", code: "zhong guo", weight: 200), .init(word: "先", code: "xian", weight: 90),
        .init(word: "西安", code: "xi an", weight: 80), .init(word: "西安市", code: "xi an shi", weight: 60),
    ])
    check(pinyin.candidates(prefix: "ni").map(\.text) == ["你", "泥", "你好", "你好啊"], "exact Pinyin candidates precede completions")
    check(pinyin.candidates(prefix: "zhongg") == [.init(text: "中国", remainingCode: "uo")], "Pinyin partial syllable completion")
    check(pinyin.candidates(prefix: "ni'h").first == .init(text: "你好", remainingCode: "ao"), "explicit syllable boundary is respected during completion")
    check(pinyin.candidates(prefix: "xi'").map(\.text) == ["西安", "西安市"], "apostrophe excludes ambiguous single-syllable spelling")
    check(pinyin.candidates(prefix: "x'ian").isEmpty, "incorrect syllable boundary does not match")
    check(pinyin.candidates(prefix: "nihao").first == .init(text: "你好", remainingCode: ""), "exact Pinyin phrase precedes longer phrase")
    check(pinyin.candidates(prefix: "Ni").isEmpty && pinyin.candidates(prefix: "ni2").isEmpty && pinyin.candidates(prefix: "").isEmpty,
          "Pinyin prefix validation preserves raw English input")
    let merged = DictionaryMerger.merge(wubiRows: [
        .init(word: "低频", code: "imde", weight: 80), .init(word: "高频", code: "imdf", weight: 10),
    ], pinyin: PinyinDictionary(rows: [
        .init(word: "低频", code: "di pin", weight: 5), .init(word: "高频", code: "gao pin", weight: 100),
    ]))
    check(merged.dictionary.candidates(prefix: "im").map(\.text) == ["高频", "低频"],
          "merged completions use real word frequency, not per-code synthetic rank")

    func session() -> Session {
        Session(pinyinLookup: pinyin.lookup, wubiCandidates: wubi.candidates, pinyinCandidates: pinyin.candidates)
    }
    var current = session()
    current.type("im")
    check(current.output.isEmpty && current.marked == "im" && current.engine.candidates == partial, "partial input remains marked while showing completions")
    current.key("", code: 125)
    current.key(" ", code: 49)
    check(current.output == "没有" && current.marked.isEmpty, "space commits selected completion without adding remaining code")
    current = session()
    current.type("imd")
    check(current.engine.candidates.first?.remainingCode == "e" && current.output.isEmpty, "pure prefix does not automatically commit")
    current.key(" ", code: 49)
    check(current.output == "没有", "space can select a candidate when no exact code exists")
    current = session()
    current.type("imd")
    current.key("\r", code: 36)
    check(current.output == "imd", "Return commits original English even when completions exist")
    current = session()
    current.type("imdez")
    check(current.marked == "imdez" && current.output.isEmpty && current.engine.choices.isEmpty, "fifth Wubi letter remains raw preedit")
    current.key("\u{7f}", code: 51)
    check(current.engine.choices == ["没有", "尚有"], "Backspace restores full-code exact candidates")
    current.key("\u{7f}", code: 51)
    check(current.engine.candidates.first?.remainingCode == "e", "Backspace restores partial-code suffix")
    current.key("\u{1b}", code: 53)
    check(current.marked.isEmpty && current.output.isEmpty, "Escape cancels completions without committing")
    current = session()
    current.type("imd")
    current.key(".")
    check(current.engine.page == 1 && current.marked == "imd", "prefix candidates can be paged")
    current.key("2")
    check(current.output == "重复词", "number selection on completion page commits only the word")
    current = session()
    current.type("imd")
    current.key(";")
    check(current.output == "没有；", "Chinese punctuation follows selected completion")
    current = session()
    current.type("imd")
    current.tapLeftShift()
    check(current.output == "imd" && current.engine.englishMode, "English-mode switch preserves incomplete code as typed")
    current.type("hello")
    check(current.output == "imdhello" && current.marked.isEmpty && current.engine.candidates.isEmpty, "English direct mode shows no completions")

    current = session()
    current.tapRightShift()
    current.type("zhongg")
    check(current.marked == "zhongg" && current.engine.candidates.first?.remainingCode == "uo", "Pinyin engine displays remaining syllable")
    current.key(" ", code: 49)
    check(current.output == "中国", "space commits Pinyin completion")
    current.type("ni")
    current.key("3")
    check(current.output == "中国你好", "numeric selection can choose Pinyin completion after exact candidates")
    current.type("xi'")
    check(current.engine.choices == ["西安", "西安市"], "Pinyin delimiter is kept during prefix lookup")
    current.key("1")
    check(current.output == "中国你好西安", "explicit-boundary completion commits")
    current.type("hello")
    current.key("\r", code: 36)
    check(current.output.hasSuffix("hello"), "unknown English still commits raw in Pinyin mode")

    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let wubiURL = root.appendingPathComponent("wubi86_jidian.dict.yaml")
    let pinyinURL = root.appendingPathComponent("pinyin_simp.dict.yaml")
    if FileManager.default.fileExists(atPath: wubiURL.path), FileManager.default.fileExists(atPath: pinyinURL.path) {
        let realPinyin = try PinyinDictionary(url: pinyinURL)
        let real = DictionaryMerger.merge(wubiRows: try DictionaryRow.read(wubiURL), pinyin: realPinyin).dictionary
        check(real.candidates(prefix: "im").contains(.init(text: "没有", remainingCode: "de")), "real Wubi im completes to 没有")
        check(realPinyin.candidates(prefix: "zhongg").contains(.init(text: "中国", remainingCode: "uo")), "real Pinyin zhongg completes to 中国")
        check(real.lookup("q") == Array(real.candidates(prefix: "q").prefix(real.lookup("q").count)).map(\.text),
              "all real exact short-code candidates remain ahead of completions")
    }
    print("PASS: prefix matching, remaining codes, completion selection and English fallback")
}
