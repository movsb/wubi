import Foundation

// All parsing, phrase generation and full reporting allocations die with this process.
guard CommandLine.arguments.count == 4 else { exit(2) }
let arguments = CommandLine.arguments
let store = DictionaryStore(resourceDirectory: URL(fileURLWithPath: arguments[1]),
                            dataDirectory: URL(fileURLWithPath: arguments[2]))
guard store.wubi.count > 0 else { exit(1) }
do {
    try store.writeSnapshot(to: URL(fileURLWithPath: arguments[3]))
} catch {
    fputs("无法写入词库索引：\(error.localizedDescription)\n", stderr)
    exit(1)
}
