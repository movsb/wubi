import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError(message) }
}
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dict.yaml")
defer { try? FileManager.default.removeItem(at: temporary) }
try """
---
name: test
...
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
if FileManager.default.fileExists(atPath: "wubi86_jidian.dict.yaml") {
    let real = try WubiDictionary(urls: [URL(fileURLWithPath: "wubi86_jidian.dict.yaml")])
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
print("PASS: \(checks) assertions")
