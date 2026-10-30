import Foundation

func runDictionaryStoreTests() throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    func merge(_ wubi: String, _ pinyin: String) throws -> DictionaryMerger.Result {
        let a = temporary.appendingPathComponent("fixture-wubi.txt")
        let b = temporary.appendingPathComponent("fixture-pinyin.txt")
        try write(wubi, to: a)
        try write(pinyin, to: b)
        return DictionaryMerger.merge(wubiRows: try DictionaryRow.read(a), pinyin: try PinyinDictionary(url: b))
    }
    let plain = temporary.appendingPathComponent("plain.txt")
    try "\u{feff}# 注释\r\n  # 缩进注释\r\n\r\n甲乙\tJIA YI # 拼音\n西安\txi'an".write(to: plain, atomically: true, encoding: .utf8)
    let plainRows = try DictionaryRow.readUserText(plain)
    check(plainRows.map(\.word) == ["甲乙", "西安"], "plain text accepts BOM, comments, CRLF, blanks and no final newline")
    check(plainRows.map(\.code) == ["jia yi", "xi an"] && plainRows.map(\.weight) == [0, 0], "plain text normalizes Pinyin without manual weights")
    for invalid in ["broken", "词\tni!", "词\tni\t100", "词\tni\t-1", "词\tni\twrong", "词\tni\t1\textra"] {
        try invalid.write(to: plain, atomically: true, encoding: .utf8)
        do {
            _ = try DictionaryRow.readUserText(plain)
            check(false, "invalid plain text must be rejected")
        } catch { check(error.localizedDescription.contains("plain.txt"), "invalid plain text reports filename and format error") }
    }
    let exclusionSaveURL = temporary.appendingPathComponent("saved-exclusions.txt")
    try write("# 保留注释\r\n原词 # 已排除", to: exclusionSaveURL)
    try DictionaryRow.exclude("甲乙", at: exclusionSaveURL)
    try DictionaryRow.exclude("原词", at: exclusionSaveURL)
    try DictionaryRow.exclude("甲乙", at: exclusionSaveURL)
    let savedExclusions = try String(contentsOf: exclusionSaveURL, encoding: .utf8)
    check(savedExclusions == "# 保留注释\r\n原词 # 已排除\n甲乙\n",
          "candidate deletion preserves comments, adds a missing newline and avoids duplicate words")
    for invalid in ["", "词\n语", "词#语", "词\t语"] {
        do {
            try DictionaryRow.exclude(invalid, at: exclusionSaveURL)
            check(false, "invalid exclusion must be rejected")
        } catch { check(true, "invalid exclusion is rejected") }
    }
    let lineFixture = temporary.appendingPathComponent("line-endings.txt")
    try "# 注释\r\n甲\tabcd\t12%\r\n乙\tefgh\tNaN\r丙\tijkl\t3".write(to: lineFixture, atomically: true, encoding: .utf8)
    let lineRows = try DictionaryRow.read(lineFixture)
    check(lineRows.map(\.word) == ["甲", "乙", "丙"], "streaming parser handles CRLF, CR and an unterminated last line")
    check(lineRows.map(\.weight) == [12, 0, 3], "streaming parser preserves percent and nonfinite weight handling")
    let reportRows = (1...40).map { DictionaryRow(word: "甲" + String(repeating: "乙", count: $0), code: "jia " + Array(repeating: "yi", count: $0).joined(separator: " "), weight: Double($0)) }
    let reportResult = DictionaryMerger.merge(wubiRows: [.init(word: "甲", code: "abcd", weight: 1), .init(word: "乙", code: "efgh", weight: 1)], pinyin: PinyinDictionary(rows: reportRows))
    try reportResult.report.write(to: temporary)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let reportURL = temporary.appendingPathComponent("dictionary-merge-report.json")
    let firstReportData = try Data(contentsOf: reportURL)
    let decodedReport = try decoder.decode(DictionaryMergeReport.self, from: firstReportData)
    check(decodedReport.newPhrases.count == 40 && decodedReport.newPhrases.first?.roots == ["甲": "abcd", "乙": "efgh"], "streamed report preserves every entry and per-word roots")
    check(reportResult.report.summary().newPhrases.count == 30 && reportResult.report.summary().addedPhrases == 40, "resident report summary is bounded without truncating total counts")
    try reportResult.report.write(to: temporary)
    let secondReportData = try Data(contentsOf: reportURL)
    check(secondReportData == firstReportData, "atomic streamed report replacement is deterministic")
    let roots = ["甲": "abcd", "乙": "efgh", "丙": "ijkl", "丁": "mnop", "戊": "qrst"]
    check(DictionaryMerger.phraseCode("甲乙", roots: roots) == "abef", "two-character Wubi phrase rule")
    check(DictionaryMerger.phraseCode("甲乙丙", roots: roots) == "aeij", "three-character Wubi phrase rule")
    check(DictionaryMerger.phraseCode("甲乙丙丁", roots: roots) == "aeim", "four-character Wubi phrase rule")
    check(DictionaryMerger.phraseCode("甲乙丙丁戊", roots: roots) == "aeiq", "long Wubi phrase rule")
    check(DictionaryMerger.phraseCode("甲未知", roots: roots) == nil, "missing character code skipped")
    check(DictionaryMerger.phraseCode("甲A", roots: roots) == nil, "non-Hanzi phrase skipped")
    check(DictionaryMerger.phraseCode("甲", roots: roots) == nil, "single character not guessed")

    var result = try merge("我\tq\t20\n金\tq\t10\n甲乙\tabe\t20\n", "金\tjin\t999999\n我\two\t1\n")
    check(result.dictionary.lookup("q") == ["我", "金"] && result.dictionary.lookup("abe") == ["甲乙"], "all short-code rankings protected")
    check(result.report.protectedShortCodes == 2, "protected short-code report")
    result = try merge("甲\tabcd\t20\n乙\tefgh\t20\n原词\tabef\t80\n", "原词\tyuan ci\t5\n甲乙\tjia yi\t100\n")
    check(result.dictionary.lookup("abef") == ["甲乙", "原词"], "existing and generated words use same frequency scale")
    check(result.report.addedPhrases == 1 && result.report.firstCandidateChanges.first?.after == "甲乙", "new-word and ranking-change report")
    result = try merge("原词\tabcd\t80\n新词\tabcd\t10\n", "原词\tyuan ci\t5\n新词\txin ci\t100\n")
    check(result.dictionary.lookup("abcd") == ["新词", "原词"], "existing words are reranked using Pinyin frequency")
    result = try merge("低频\tabcd\t10\n高频\tabcd\t20\n", "")
    check(result.dictionary.lookup("abcd") == ["高频", "低频"], "missing frequency preserves original order")
    result = try merge("低频\tabcd\t10\n高频\tabcd\t20\n", "低频\tdi pin\t5\n高频\tgao pin\t5\n")
    check(result.dictionary.lookup("abcd") == ["高频", "低频"], "equal frequency preserves original order")
    result = try merge("甲\tabcd\t20\n乙\tefgh\t20\n甲乙\twxyz\t20\n", "甲乙\tjia yi\t100\n")
    check(result.dictionary.lookup("abef").isEmpty && result.report.addedPhrases == 0, "existing word does not receive another guessed code")
    result = try merge("甲\ta\t100\n甲\tabcd\t20\n甲\twxyz\t10\n乙\tefgh\t20\n", "甲乙\tjia yi\t100\n")
    check(result.dictionary.lookup("abef") == ["甲乙"], "root selection prefers full code then original weight")
    result = try merge("甲\tab\t20\n乙\tefg\t20\n", "甲乙\tjia yi\t100\n")
    check(result.dictionary.lookup("abef") == ["甲乙"], "legitimate two- and three-letter full character codes")
    result = try merge("甲\tabcd\t20\n甲\tabcd\t20\n乙\tefgh\t20\n原词\tabef\t20\n",
                       "甲乙\tjia yi\t10\n甲乙\tjia yi\t10\n甲乙\tga yi\t5\n原词\tyuan ci\t12\n")
    check(result.dictionary.lookup("abef") == ["原词", "甲乙"] && result.report.originalEntries == 3,
          "duplicate Wubi entries and Pinyin pronunciations do not inflate ranking")
    check(result.report.newPhrases.first?.frequency == 10, "multiple pronunciations use maximum frequency")
    result = try merge("甲\tabcd\t20\n", "甲乙\tjia yi\t10\n")
    check(result.report.skipped.first?.missingCharacters == ["乙"], "report identifies missing character codes")

    let resources = temporary.appendingPathComponent("Resources", isDirectory: true)
    let data = temporary.appendingPathComponent("UserData", isDirectory: true)
    let baseURL = resources.appendingPathComponent("wubi86_jidian.txt")
    let baseText = "甲\tabcd\t20\n乙\tefgh\t20\n丙\tijkl\t20\n原词\tabef\t80\n我\tq\t20\n金\tq\t10\n"
    try write(baseText, to: baseURL)
    try write("甲乙\tjia yi\t100\n原词\tyuan ci\t5\n你\tni\t1000\n", to: resources.appendingPathComponent("pinyin_simp.txt"))
    let store = DictionaryStore(resourceDirectory: resources, dataDirectory: data, log: { _ in })
    check(store.pinyin.frequencies.isEmpty && store.pinyin.wordsInOrder.isEmpty, "runtime releases merge-only Pinyin metadata")
    check(store.wubi.lookup("abef") == ["甲乙", "原词"] && store.report?.addedPhrases == 1, "startup merges raw bundled dictionaries")
    check(store.wubi.lookup("ni").isEmpty && store.pinyin.lookup("ni") == ["你"], "Pinyin codes are never loaded as Wubi codes")
    check(!FileManager.default.fileExists(atPath: data.appendingPathComponent("Dictionaries").path), "startup does not create a legacy dictionary directory")
    try write("旧词\tjiu ci\n", to: data.appendingPathComponent("Dictionaries/ignored.txt"))
    check(store.reload() && store.pinyin.lookup("jiuci").isEmpty, "legacy Dictionaries files are not loaded")
    check(FileManager.default.fileExists(atPath: data.appendingPathComponent("tmp/dictionary-merge-report.md").path), "runtime report is written to disposable tmp directory")
    let usage = WordUsageStore(url: temporary.appendingPathComponent("frequencies.txt"))
    var engine = InputEngine(lookup: { store.wubi.lookup($0) }, pinyinLookup: { store.pinyin.lookup($0) }, usage: usage)
    check(store.wubi.candidates(prefix: "aei").isEmpty, "empty prefix result can be cached before user dictionary update")
    let userPinyin = data.appendingPathComponent("manual.txt")
    try "# 用户词库，无文件头\n\n甲乙丙\tjia yi bing # 常用词\n".write(to: userPinyin, atomically: true, encoding: .utf8)
    check(store.reload(), "user dictionary reload succeeds without rebuilding")
    check(store.wubi.candidates(prefix: "aei") == [.init(text: "甲乙丙", remainingCode: "j")], "runtime reload invalidates old prefix cache")
    check(store.pinyin.lookup("jiayibing") == ["甲乙丙"], "unified custom word loads in Pinyin")
    check(store.wubi.lookup("aeij") == ["甲乙丙"], "custom Pinyin word automatically receives a Wubi code")
    check(store.wubi.reverseLookup("甲乙丙") == "aeij", "generated user word supports Wubi reverse lookup")
    for char in "aeij" { _ = engine.handle(InputKey(text: String(char))) }
    check(engine.choices == ["甲乙丙"], "existing engine sees refreshed dictionaries through store")
    check(engine.handle(InputKey(text: " ", code: 49)).effects == [.insert("甲乙丙")], "generated runtime word commits through existing engine")
    check(usage.counts["甲乙丙"] == 1, "confirming a user word automatically records usage without a manual weight")
    var deletionEngine = InputEngine(lookup: { store.wubi.lookup($0) })
    for char in "aeij" { _ = deletionEngine.handle(InputKey(text: String(char))) }
    try DictionaryRow.exclude("甲乙丙", at: data.appendingPathComponent("excluded.txt"))
    check(store.reload(), "candidate deletion reloads the exclusion dictionary")
    deletionEngine.refreshCandidates()
    check(deletionEngine.code == "aeij" && deletionEngine.choices.isEmpty && deletionEngine.selectedIndex == 0,
          "candidate deletion preserves preedit without committing when the final candidate disappears")
    try FileManager.default.removeItem(at: data.appendingPathComponent("excluded.txt"))
    try FileManager.default.removeItem(at: userPinyin)
    check(store.reload() && store.wubi.lookup("aeij").isEmpty && store.pinyin.lookup("jiayibing").isEmpty, "removing unified user dictionary removes both modes on reload")
    check(store.wubi.candidates(prefix: "aei").isEmpty && store.wubi.reverseLookup("甲乙丙") == nil, "removed user word disappears from prefix and reverse indices")

    let settings = data.appendingPathComponent("settings.json")
    try "{\"mergePinyinIntoWubi\":false}".write(to: settings, atomically: true, encoding: .utf8)
    check(store.reload() && !store.mergeEnabled && store.report == nil, "runtime settings can disable merge without rebuilding")
    check(store.wubi.lookup("abef") == ["原词"] && store.pinyin.lookup("jiayi") == ["甲乙"], "disabling merge preserves independent Pinyin dictionary")
    check(!FileManager.default.fileExists(atPath: data.appendingPathComponent("tmp/dictionary-merge-report.json").path), "disabled merge removes stale report")
    try "{}".write(to: settings, atomically: true, encoding: .utf8)
    check(store.reload() && store.mergeEnabled && store.wubi.lookup("abef").first == "甲乙", "default settings re-enable runtime merge")
    let excludedURL = data.appendingPathComponent("excluded.txt")
    try write("甲乙丙\tjia yi bing\n", to: userPinyin)
    try write("\u{feff}# 排除词库\r\n  原词 # 内置词\r甲乙\n甲乙丙\n甲乙\n\n", to: excludedURL)
    check(store.reload(), "exclusions accept BOM, comments, CRLF, CR, blanks and duplicates")
    check(store.wubi.lookup("abef").isEmpty && store.pinyin.lookup("jiayi").isEmpty
          && store.pinyin.lookup("yuanci").isEmpty, "exclusions remove bundled and generated words in both modes")
    check(store.wubi.lookup("aeij").isEmpty && store.pinyin.lookup("jiayibing").isEmpty,
          "exclusions override manual words")
    check(store.wubi.candidates(prefix: "aei").isEmpty && store.wubi.reverseLookup("甲乙丙") == nil
          && store.pinyin.candidates(prefix: "jia").isEmpty, "excluded words disappear from prefix and reverse indices")
    check(store.report?.newPhrases.isEmpty == true && store.wubi.lookup("abcd") == ["甲"],
          "excluded words are not generated and unrelated words remain")
    try write("{\"mergePinyinIntoWubi\":false}", to: settings)
    check(store.reload() && store.wubi.lookup("abef").isEmpty && store.pinyin.lookup("jiayi").isEmpty,
          "exclusions also apply when automatic merge is disabled")
    try write("{}", to: settings)
    try FileManager.default.removeItem(at: excludedURL)
    check(store.reload() && store.wubi.lookup("abef") == ["甲乙", "原词"]
          && store.pinyin.lookup("jiayibing") == ["甲乙丙"], "removing exclusions restores words on reload")
    try write("甲乙", to: excludedURL)
    check(store.reload() && store.wubi.lookup("aeij") == ["甲乙丙"], "exclusions match whole words only")
    try write("甲\n乙\n丙\n原词\n我\n金\n甲乙\n甲乙丙", to: excludedURL)
    check(store.reload() && store.wubi.count == 0 && store.hasLoadedSnapshot,
          "excluding every Wubi word produces a valid empty snapshot")
    try write("甲乙", to: excludedURL)
    check(store.reload(), "reload restores candidates after an empty snapshot")
    try Data([0xff]).write(to: excludedURL)
    check(!store.reload() && store.wubi.lookup("aeij") == ["甲乙丙"]
          && store.issues.contains { $0.contains("excluded.txt") }, "unreadable exclusion file preserves previous snapshot and reports error")
    try FileManager.default.removeItem(at: excludedURL)
    try FileManager.default.removeItem(at: userPinyin)
    check(store.reload(), "restoring valid exclusion inputs reloads successfully")
    let firstReport = try Data(contentsOf: data.appendingPathComponent("tmp/dictionary-merge-report.json"))
    _ = store.reload()
    let secondReport = try Data(contentsOf: data.appendingPathComponent("tmp/dictionary-merge-report.json"))
    check(firstReport == secondReport, "unchanged dictionaries produce deterministic runtime report")
    try FileManager.default.removeItem(at: data.appendingPathComponent("tmp"))
    check(store.reload(), "deleting disposable tmp directory does not break dictionary reload")
    check(FileManager.default.fileExists(atPath: data.appendingPathComponent("tmp/dictionary-merge-report.json").path)
          && FileManager.default.fileExists(atPath: data.appendingPathComponent("tmp/dictionary-load-issues.log").path),
          "reload recreates reports and issues log in tmp")
    check(!FileManager.default.fileExists(atPath: data.appendingPathComponent("dictionary-merge-report.json").path)
          && !FileManager.default.fileExists(atPath: data.appendingPathComponent("dictionary-load-issues.log").path),
          "generated reports and logs never clutter persistent data directory")

    try "broken".write(to: userPinyin, atomically: true, encoding: .utf8)
    try "broken".write(to: settings, atomically: true, encoding: .utf8)
    check(store.reload() && store.wubi.lookup("q").first == "我", "malformed user dictionary and settings do not break bundled dictionaries")
    check(store.issues.count == 2, "invalid user file and settings are diagnosed")
    try "甲乙丁\tjia yi ding\n".write(to: userPinyin, atomically: true, encoding: .utf8)
    _ = store.reload()
    check(store.report?.skipped.contains { $0.word == "甲乙丁" && $0.missingCharacters == ["丁"] } == true,
          "runtime merge reports custom phrase missing character code")
    try write(baseText + "丁\tmnop\t20\n", to: baseURL)
    try FileManager.default.removeItem(at: settings)
    _ = store.reload()
    check(store.wubi.lookup("aemn") == ["甲乙丁"], "updated bundled character code enables previously skipped phrase")
    let newProcess = DictionaryStore(resourceDirectory: resources, dataDirectory: data, log: { _ in })
    check(newProcess.wubi.lookup("aemn") == ["甲乙丁"], "user dictionaries persist across store initialization")
    let currentBytes = try Data(contentsOf: baseURL)
    check(currentBytes == Data((baseText + "丁\tmnop\t20\n").utf8), "runtime merge never modifies updated base dictionary")
    try FileManager.default.removeItem(at: baseURL)
    check(!store.reload() && store.wubi.lookup("aemn") == ["甲乙丁"], "failed reload preserves last working dictionary snapshot")

    let blocked = temporary.appendingPathComponent("not-a-directory")
    try Data().write(to: blocked)
    try write(baseText, to: baseURL)
    let readOnly = DictionaryStore(resourceDirectory: resources, dataDirectory: blocked, log: { _ in })
    check(readOnly.wubi.lookup("q").first == "我" && !readOnly.issues.isEmpty, "unwritable data directory still allows bundled input")
    try write("旧生成词\tzzzz\t1\n", to: resources.appendingPathComponent("wubi_merged.txt"))
    let ignoresStale = DictionaryStore(resourceDirectory: resources, dataDirectory: temporary.appendingPathComponent("FreshData"), log: { _ in })
    check(ignoresStale.wubi.lookup("zzzz").isEmpty, "legacy compile-time merged dictionary is ignored")
    print("PASS: runtime merge, user dictionaries, reload, reports and failure recovery")

    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let wubiURL = root.appendingPathComponent("wubi86_jidian.txt")
    let pinyinURL = root.appendingPathComponent("pinyin_simp.txt")
    if FileManager.default.fileExists(atPath: wubiURL.path), FileManager.default.fileExists(atPath: pinyinURL.path) {
        let wubiRows = try DictionaryRow.read(wubiURL)
        let base = WubiDictionary(rows: wubiRows)
        let merged = DictionaryMerger.merge(wubiRows: wubiRows, pinyin: try PinyinDictionary(url: pinyinURL))
        let shortCodes = Set(wubiRows.compactMap(\.wubiCode).filter { $0.count < 4 })
        check(shortCodes.allSatisfy { base.lookup($0) == merged.dictionary.lookup($0) }, "all real short-code candidate orders are unchanged")
        check(wubiRows.allSatisfy { row in
            guard let code = row.wubiCode else { return true }
            return merged.dictionary.lookup(code).contains(row.word)
        }, "runtime merge preserves every original valid Wubi entry")
        check(merged.dictionary.lookup("gijg").contains("不是") && merged.dictionary.lookup("trjg").contains("我是"), "real Pinyin words receive Wubi codes at runtime")
        check(merged.report.addedPhrases > 15000 && merged.dictionary.count == merged.report.mergedEntries, "runtime report agrees with loaded dictionary count")
        print("PASS: real runtime merge; \(merged.report.addedPhrases) new words, \(shortCodes.count) short-code groups protected")
    }
}

func runBackgroundReloadTests() throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let resources = temporary.appendingPathComponent("resources")
    let data = temporary.appendingPathComponent("user")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    let base = resources.appendingPathComponent("wubi.txt")
    try "甲\tabcd\n".write(to: base, atomically: true, encoding: .utf8)
    let lock = NSLock()
    var loadedOffMain = false
    let store = DictionaryStore(resourceDirectory: resources, dataDirectory: data) { _ in
        lock.lock()
        if !Thread.isMainThread { loadedOffMain = true }
        lock.unlock()
    }
    func wait(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        check(predicate(), "background reload finishes within timeout")
    }
    try "乙\tefgh\n".write(to: base, atomically: true, encoding: .utf8)
    var complete = false
    store.reloadInBackground { success in
        check(success && Thread.isMainThread, "background snapshot publishes on main thread")
        complete = true
    }
    check(!complete && store.wubi.lookup("abcd") == ["甲"], "input keeps old snapshot while rebuild is pending")
    wait { complete }
    lock.lock(); let offMain = loadedOffMain; lock.unlock()
    check(offMain && store.wubi.lookup("efgh") == ["乙"], "dictionary work runs off main and becomes visible after publication")

    try FileManager.default.removeItem(at: base)
    complete = false
    store.reloadInBackground { success in
        check(!success, "failed background refresh reports failure")
        complete = true
    }
    wait { complete }
    check(store.wubi.lookup("efgh") == ["乙"], "failed background refresh preserves previous dictionary")

    try "丙\tijkl\n".write(to: base, atomically: true, encoding: .utf8)
    var staleCallback = false
    store.reloadInBackground { _ in staleCallback = true }
    check(store.reload(), "explicit reload supersedes pending background request")
    try "丁\tmnop\n".write(to: base, atomically: true, encoding: .utf8)
    complete = false
    store.reloadInBackground { success in
        check(success, "latest background request succeeds")
        complete = true
    }
    wait { complete }
    check(!staleCallback && store.wubi.lookup("mnop") == ["丁"] && store.wubi.lookup("ijkl").isEmpty,
          "superseded work never publishes an old snapshot or completion")
    print("PASS: background reload, snapshot publication, failure recovery and stale request suppression")
}
