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
try Data("invalid".utf8).write(to: usageURL)
check(WordUsageStore(url: usageURL).counts.isEmpty, "invalid usage file falls back to dictionary order")
print("PASS: personal word usage checks")
print("PASS: \(checks) assertions")
