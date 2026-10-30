import Foundation
import Darwin

@discardableResult
func memory(_ label: String) -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    precondition(status == KERN_SUCCESS)
    print(String(format: "%@: footprint %.2f MiB", label, Double(info.phys_footprint) / 1048576))
    fflush(stdout)
    return info.phys_footprint
}

let bundle = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Contents")
let resources = bundle.appendingPathComponent("Resources")
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let user = temporary.appendingPathComponent("user")
defer { try? FileManager.default.removeItem(at: temporary) }
let store = DictionaryStore(resourceDirectory: resources, dataDirectory: user,
    builderURL: bundle.appendingPathComponent("MacOS/WubiDictionaryBuilder"), log: { _ in })
var engine = InputEngine(lookup: { store.wubi.lookup($0) }, readings: { store.pinyin.readings(for: $0) })
precondition(store.hasLoadedSnapshot && store.wubi.count > 100000, "常驻词库加载失败，内存结果无效")
let baseline = memory("加载后")
for round in 1...3 {
    _ = engine.handle(InputKey(text: "w"))
    _ = engine.handle(InputKey(text: "*"))
    let request = engine.externalRequest!
    try autoreleasepool {
        let directory = temporary.appendingPathComponent("query-\(round)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let process = Process()
        process.executableURL = bundle.appendingPathComponent("MacOS/WubiExternalQuery")
        process.arguments = [resources.path, user.path, "w", "--index-dir", directory.path]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        let results = try ExternalCandidates(directory: directory) { store.wubi.reverseLookup($0) == nil }
        precondition(results.count > 50000, "请先下载雾凇 cn_dicts 并重新构建")
        _ = engine.receiveExternal(results, request: request)
        memory("第 \(round) 次展开（\(results.count) 个新词）")
    }
    autoreleasepool {
        for _ in 0..<100 {
            _ = engine.handle(InputKey(code: 125))
            precondition(engine.visibleCandidates.count == 5)
        }
    }
    let browsing = memory("第 \(round) 次翻页后")
    precondition(browsing < baseline + 8 * 1048576, "候选浏览增加的物理占用超过 8 MiB")
    _ = engine.handle(InputKey(code: 53))
    _ = engine.handle(InputKey(code: 53))
    let cleared = memory("第 \(round) 次取消后")
    precondition(cleared < baseline + 8 * 1048576, "取消后未释放扩展结果")
}
// This many polyphonic combinations must remain a count plus a five-row page.
var polyphonic = InputEngine(lookup: { _ in [] }, readings: { _ in ["a", "ai", "an", "ang", "ao"] })
_ = polyphonic.handle(InputKey(text: "a"))
_ = polyphonic.handle(InputKey(text: "*"))
_ = polyphonic.receiveExternal([String(repeating: "重", count: 12)], request: polyphonic.externalRequest!)
_ = polyphonic.handle(InputKey(code: 49))
precondition(polyphonic.candidateCount == 244_140_625 && polyphonic.visibleCandidates.count == 5)
memory("2.44 亿拼音组合仅生成当前页")
print("PASS: large external query mappings, bounded browsing memory and lazy pronunciation pages")
