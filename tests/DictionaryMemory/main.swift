import Foundation
import Darwin

let limit = UInt64(ProcessInfo.processInfo.environment["WUBI_MEMORY_LIMIT_MB"] ?? "128") ?? 128

func memory(_ label: String) {
    var info = task_vm_info_data_t()
    var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size)
        }
    }
    precondition(status == KERN_SUCCESS)
    print("\(label): RSS \(info.resident_size / 1048576) MiB; footprint \(info.phys_footprint / 1048576) MiB")
    fflush(stdout)
    precondition(info.phys_footprint < limit * 1048576, "物理内存超过 \(limit) MiB")
}
let data = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: data) }
let store = DictionaryStore(resourceDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath), dataDirectory: data, builderURL: URL(fileURLWithPath: CommandLine.arguments[1]), log: { _ in })
precondition(store.issues.isEmpty && store.pinyin.count > 60000 && store.report!.addedPhrases > 15000)
memory("加载后")
for _ in 0..<2 {
    autoreleasepool {
        for prefix in ["a", "s", "z", "ab", "zh", "zhong", "xian", "xi'"] {
            _ = store.wubi.candidates(prefix: prefix)
            _ = store.pinyin.candidates(prefix: prefix)
        }
    }
}
memory("前缀查询后")
precondition(store.reload() && store.issues.isEmpty)
memory("重新加载后")
precondition(store.pinyin.lookup("nihao").contains("你好"))
precondition(!store.pinyin.lookup("sanguoqunyingzhuan").contains("三国群英传"))

// Exercise the subprocess boundary with user updates and a failed rebuild.
let fixtureResources = data.appendingPathComponent("FixtureResources")
let fixtureData = data.appendingPathComponent("FixtureData")
try FileManager.default.createDirectory(at: fixtureResources, withIntermediateDirectories: true)
let fixtureWubi = fixtureResources.appendingPathComponent("wubi.txt")
try "甲\tabcd\t1\n乙\tefgh\t1\n".write(to: fixtureWubi, atomically: true, encoding: .utf8)
try "甲乙\tjia yi\t100\n".write(to: fixtureResources.appendingPathComponent("pinyin_simp.txt"), atomically: true, encoding: .utf8)
let fixtureStore = DictionaryStore(resourceDirectory: fixtureResources, dataDirectory: fixtureData,
                                   builderURL: URL(fileURLWithPath: CommandLine.arguments[1]), log: { _ in })
precondition(fixtureStore.wubi.lookup("abef") == ["甲乙"] && fixtureStore.issues.isEmpty)
try "# 用户词库\n甲乙乙\tjia yi yi\n".write(to: fixtureData.appendingPathComponent("manual.txt"), atomically: true, encoding: .utf8)
precondition(fixtureStore.reload() && fixtureStore.wubi.lookup("aeef") == ["甲乙乙"])
try FileManager.default.removeItem(at: fixtureWubi)
precondition(!fixtureStore.reload() && fixtureStore.wubi.lookup("aeef") == ["甲乙乙"])
print("PASS: subprocess user dictionary reload and failed rebuild preserve active mappings")
