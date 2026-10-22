import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError(message) }
}
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
defer { try? FileManager.default.removeItem(at: temporary) }
try """
金\tq\t10
我\tq\t20
我\tq\t20
没有\timde\t10
错误\tbad!\t100
表情\tzzzz\t5\tstem
""".write(to: temporary, atomically: true, encoding: .utf8)
let fixture = try WubiDictionary(urls: [temporary])
check(fixture.lookup("q") == ["我", "金"], "weight ordering and deduplication")
check(fixture.lookup("Q") == ["我", "金"], "uppercase lookup")
check(fixture.lookup("bad!").isEmpty, "invalid code")
check(fixture.lookup("zzzz") == ["表情"], "additional columns")
check(fixture.lookup("missing").isEmpty, "missing code")
if FileManager.default.fileExists(atPath: "wubi86_jidian.txt") {
    let real = try WubiDictionary(urls: [URL(fileURLWithPath: "wubi86_jidian.txt")])
    check(real.count > 50000, "full dictionary loaded")
    check(real.lookup("q").first == "我", "first candidate")
    check(real.lookup("imde").contains("没有"), "four-letter phrase")
    check(real.lookup("qytr").contains("勿忘我"), "original example")
    print("PASS: full dictionary checks; loaded \(real.count) entries")
} else {
    print("SKIP: optional downloaded dictionary; fixture tests still run")
}

var punctuation = ChinesePunctuation()
check(punctuation.convert(",") == "，", "Chinese comma")
check(punctuation.convert(".") == "。", "Chinese full stop")
check(punctuation.convert("\\") == "、", "enumeration comma")
check(punctuation.convert("^") == "……", "ellipsis")
check(punctuation.convert("_") == "——", "em dash")
check(punctuation.convert("\"") == "“", "opening double quote")
check(punctuation.convert("'") == "‘", "independent opening single quote")
check(punctuation.convert("\"") == "”", "closing double quote")
check(punctuation.convert("'") == "’", "closing single quote")
_ = punctuation.convert("\"")
punctuation.reset()
check(punctuation.convert("\"") == "“", "quote reset after session change")
check(punctuation.convert("-") == nil && punctuation.convert("=") == nil, "paging keys unchanged")
check(punctuation.convert("1") == nil && punctuation.convert("a") == nil, "non-punctuation passthrough")
print("PASS: punctuation and quote state checks")
runInputEngineTests()
runKeyEventTests()
try runPinyinTests()
try runDictionaryStoreTests()
try runProcessLifecycleTests()
try runPrefixTests()

let usageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("usage.json")
defer { try? FileManager.default.removeItem(at: usageURL.deletingLastPathComponent()) }
let usage = WordUsageStore(url: usageURL, saveDelay: 0.3)
var learning = InputEngine(lookup: { _ in ["甲", "乙", "丙"] },
                           pinyinLookup: { _ in ["丙", "乙", "甲"] }, usage: usage)
_ = learning.handle(InputKey(text: "a"))
check(learning.choices == ["甲", "乙", "丙"], "initial dictionary order")
_ = learning.handle(InputKey(text: "2"))
check(usage.counts == ["乙": 1], "number selection learns word")
_ = learning.handle(InputKey(text: "b"))
_ = learning.handle(InputKey(text: "b"))
_ = learning.handle(InputKey(text: "b"))
_ = learning.handle(InputKey(text: "b"))
check(learning.choices == ["乙", "甲", "丙"], "usage shared across codes; ties preserve dictionary order")
_ = learning.handle(InputKey(code: 49))
check(usage.counts["乙"] == 2, "space selection increments usage")
_ = learning.handle(InputKey(text: "a"))
_ = learning.handle(InputKey(code: 36))
check(usage.counts == ["乙": 2], "raw Return commit does not learn")
_ = learning.handle(InputKey(code: 60, isModifierChange: true, rightShiftDown: true))
_ = learning.handle(InputKey(code: 60, isModifierChange: true))
_ = learning.handle(InputKey(text: "y"))
check(learning.choices == ["乙", "丙", "甲"], "usage shared across modes")
_ = learning.deactivate()
check(usage.counts["乙"] == 3, "deactivation candidate commit learns")
check(!FileManager.default.fileExists(atPath: usageURL.path), "selection does not immediately write usage")
RunLoop.main.run(until: Date().addingTimeInterval(0.18))
usage.record("乙")
RunLoop.main.run(until: Date().addingTimeInterval(0.18))
check(!FileManager.default.fileExists(atPath: usageURL.path), "new selection resets idle timer")
let saveDeadline = Date().addingTimeInterval(2)
while !FileManager.default.fileExists(atPath: usageURL.path) && Date() < saveDeadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
}
check(FileManager.default.fileExists(atPath: usageURL.path), "idle timeout saves usage")
let restoredUsage = WordUsageStore(url: usageURL)
check(restoredUsage.counts == usage.counts, "usage survives reloading")
restoredUsage.record("甲")
restoredUsage.record("甲")
restoredUsage.record("甲")
restoredUsage.record("甲")
check(restoredUsage.rank([InputCandidate(text: "甲", remainingCode: "bc"), InputCandidate(text: "乙", remainingCode: "")]).first?.text == "乙", "exact match precedes completion with equal usage")
restoredUsage.record("甲")
let rankedGroups = restoredUsage.rank([
    InputCandidate(text: "甲", remainingCode: "bc"),
    InputCandidate(text: "丙", remainingCode: ""),
    InputCandidate(text: "乙", remainingCode: ""),
    InputCandidate(text: "丁", remainingCode: "d")])
check(rankedGroups.map(\.text) == ["乙", "丙", "甲", "丁"], "exact matches precede more-used completions; usage ranks within each group")
check(rankedGroups[2].remainingCode == "bc", "ranking preserves completion metadata")
let shortUsage = WordUsageStore(url: usageURL.appendingPathExtension("short"))
shortUsage.record("月")
var shortCodes = InputEngine(lookup: { _ in ["有", "月"] }, usage: shortUsage)
for length in 1...3 {
    _ = shortCodes.handle(InputKey(text: "e"))
    check(shortCodes.choices == ["有", "月"], "Wubi \(length)-letter code preserves dictionary order after learning 月")
}
_ = shortCodes.handle(InputKey(text: "e"))
check(shortCodes.choices == ["月", "有"], "four-letter Wubi still applies personal frequency")
let prefixValues = [InputCandidate(text: "有", remainingCode: ""), InputCandidate(text: "月", remainingCode: ""),
                    InputCandidate(text: "未用词", remainingCode: "fg"), InputCandidate(text: "月", remainingCode: "g")]
var shortPrefixes = InputEngine(lookup: { _ in [] }, wubiCandidates: { _ in prefixValues }, usage: shortUsage)
_ = shortPrefixes.handle(InputKey(text: "e"))
check(shortPrefixes.candidates == prefixValues, "short Wubi preserves both exact and completion ordering")
try Data("invalid".utf8).write(to: usageURL)
check(WordUsageStore(url: usageURL).counts.isEmpty, "invalid usage file falls back to dictionary order")
print("PASS: personal word usage checks")
print("PASS: \(checks) assertions")

let manualRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: manualRoot) }
let manualURL = manualRoot.appendingPathComponent("manual.txt")
let readingsDictionary = PinyinDictionary(rows: [
    .init(word: "重", code: "zhong", weight: 10), .init(word: "重", code: "chong", weight: 5),
    .init(word: "行", code: "xing", weight: 10), .init(word: "行", code: "hang", weight: 5),
])
let combinations = try ManualReadings(word: "重行", readings: readingsDictionary.readings)
check(combinations.count == 4, "manual phrase enumerates all polyphonic combinations")
check((0..<4).compactMap(combinations.spelling) == ["zhong xing", "zhong hang", "chong xing", "chong hang"], "manual readings stable ordering")
check(combinations.spelling(at: 4) == nil, "manual readings reject out of bounds selection")
do {
    _ = try ManualReadings(word: "未知", readings: readingsDictionary.readings)
    check(false, "missing pronunciation must fail")
} catch {}
try ManualReadings.save(word: "重行", spelling: "chong hang", to: manualURL)
try ManualReadings.save(word: "重行", spelling: "chong hang", to: manualURL)
try ManualReadings.save(word: "重行", spelling: "zhong xing", to: manualURL)
let savedManualRows = try DictionaryRow.readUserText(manualURL)
check(savedManualRows.count == 2, "manual save deduplicates and preserves alternative readings")
let manualBeforeInvalidSave = try Data(contentsOf: manualURL)
for (invalidWord, invalidSpelling) in [
    ("重\n行", "chong hang"), ("重\r\n行", "chong hang"),
    ("重\t行", "chong hang"), ("重\u{2028}行", "chong hang"),
    ("重行", "chong\nhang"), ("重行", "chong\thang"),
] {
    do {
        try ManualReadings.save(word: invalidWord, spelling: invalidSpelling, to: manualURL)
        check(false, "save must reject record separators in word or spelling")
    } catch {}
    let afterInvalidSave = try Data(contentsOf: manualURL)
    check(afterInvalidSave == manualBeforeInvalidSave, "invalid save must leave manual.txt byte-for-byte unchanged")
}
let manualResources = manualRoot.appendingPathComponent("resources")
try FileManager.default.createDirectory(at: manualResources, withIntermediateDirectories: true)
try "重\ttgjf\t1\n行\ttfhh\t1\n".write(to: manualResources.appendingPathComponent("wubi.txt"), atomically: true, encoding: .utf8)
try "重\tzhong\t1\n行\txing\t1\n".write(to: manualResources.appendingPathComponent("pinyin_simp.txt"), atomically: true, encoding: .utf8)
let manualStore = DictionaryStore(resourceDirectory: manualResources, dataDirectory: manualRoot, log: { _ in })
check(manualStore.pinyin.lookup("chonghang") == ["重行"], "root manual.txt loads selected pronunciation")
check(manualStore.wubi.lookup("tgtf") == ["重行"], "manual phrase generates Wubi code")
let manualSnapshot = manualRoot.appendingPathComponent("snapshot")
try manualStore.writeSnapshot(to: manualSnapshot)
let mappedReadings = try PinyinDictionary(indexDirectory: manualSnapshot, count: manualStore.pinyin.count)
check(mappedReadings.readings(for: "重") == ["zhong"], "character readings survive builder snapshot")
print("PASS: manual phrase pronunciation, persistence and runtime loading")
