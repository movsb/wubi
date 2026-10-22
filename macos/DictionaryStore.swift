import Foundation
import Darwin

final class DictionaryStore {
    static var defaultDataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wubi", isDirectory: true)
    }
    static let shared = DictionaryStore(resourceDirectory: Bundle.main.resourceURL!, dataDirectory: defaultDataDirectory,
                                        builderURL: Bundle.main.url(forAuxiliaryExecutable: "WubiDictionaryBuilder"))

    private let builderURL: URL?
    private let resourceDirectory: URL
    private let log: (String) -> Void
    let dataDirectory: URL
    private(set) var wubi = WubiDictionary(rows: [])
    private(set) var pinyin = PinyinDictionary(rows: [])
    private(set) var report: DictionaryMergeReport?
    private(set) var issues: [String] = []
    private(set) var mergeEnabled = true

    init(resourceDirectory: URL, dataDirectory: URL, builderURL: URL? = nil, log: @escaping (String) -> Void = { NSLog("%@", $0) }) {
        self.builderURL = builderURL
        self.resourceDirectory = resourceDirectory
        self.dataDirectory = dataDirectory
        self.log = log
        reload()
    }

    @discardableResult
    func reload() -> Bool {
        // Startup runs before the AppKit event loop can drain its autorelease pool.
        let success = autoreleasepool { builderURL == nil ? reloadSnapshot() : reloadUsingBuilder() }
        // Building a large snapshot is exceptional; return its freed scratch pages to macOS.
        malloc_zone_pressure_relief(nil, 0)
        return success
    }

    private struct Snapshot: Codable {
        let wubiCount: Int
        let pinyinCount: Int
        let report: DictionaryMergeReport?
        let issues: [String]
        let mergeEnabled: Bool
    }

    func writeSnapshot(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try wubi.writeIndex(to: directory.appendingPathComponent("wubi.index"))
        try pinyin.writeIndices(to: directory)
        let snapshot = Snapshot(wubiCount: wubi.count, pinyinCount: pinyin.count, report: report,
                                issues: issues, mergeEnabled: mergeEnabled)
        try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent("snapshot.json"), options: .atomic)
    }

    private func reloadUsingBuilder() -> Bool {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Wubi-index-" + UUID().uuidString)
        // Mappings retain their open files after unlink; old snapshots survive failed reloads.
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            let process = Process()
            process.executableURL = builderURL
            process.arguments = [resourceDirectory.path, dataDirectory.path, temporary.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.standardError
            try process.run()
            process.waitUntilExit()
            guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                throw NSError(domain: "Wubi.Builder", code: Int(process.terminationStatus),
                              userInfo: [NSLocalizedDescriptionKey: "词库构建失败，保留此前的运行时词库"])
            }
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: temporary.appendingPathComponent("snapshot.json")))
            guard snapshot.wubiCount > 0 else { throw NSError(domain: "Wubi.Builder", code: 1) }
            let nextWubi = try WubiDictionary(indexURL: temporary.appendingPathComponent("wubi.index"), count: snapshot.wubiCount)
            let nextPinyin = try PinyinDictionary(indexDirectory: temporary, count: snapshot.pinyinCount)
            wubi = nextWubi
            pinyin = nextPinyin
            report = snapshot.report
            issues = snapshot.issues
            mergeEnabled = snapshot.mergeEnabled
            return true
        } catch {
            issues = [error.localizedDescription]
            log("Wubi dictionaries: " + error.localizedDescription)
            return false
        }
    }

    @inline(never)
    private func reloadSnapshot() -> Bool {
        var problems: [String] = []
        let userDictionary = dataDirectory.appendingPathComponent("Dictionaries", isDirectory: true)
        do { try FileManager.default.createDirectory(at: userDictionary, withIntermediateDirectories: true) }
        catch { problems.append("无法创建词库目录：\(error.localizedDescription)") }
        func files(_ directory: URL, suffix: String = ".txt") -> [URL] {
            do {
                return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasSuffix(suffix) }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
            } catch {
                problems.append("无法读取 \(directory.path)：\(error.localizedDescription)")
                return []
            }
        }
        func rows(_ urls: [URL], userText: Bool = false) -> [DictionaryRow] {
            urls.flatMap { url -> [DictionaryRow] in
                do { return try userText ? DictionaryRow.readUserText(url) : DictionaryRow.read(url) }
                catch {
                    problems.append("跳过 \(url.path)：\(error.localizedDescription)")
                    return []
                }
            }
        }
        let bundled = files(resourceDirectory)
        let wubiRows = rows(bundled.filter { $0.lastPathComponent.hasPrefix("wubi") && $0.lastPathComponent != "wubi_merged.txt" })
        let pinyinRows = rows(bundled.filter { $0.lastPathComponent == "pinyin_simp.txt" })
            + rows(files(userDictionary, suffix: ".txt"), userText: true)
            + rows(FileManager.default.fileExists(atPath: dataDirectory.appendingPathComponent("manual.txt").path)
                   ? [dataDirectory.appendingPathComponent("manual.txt")] : [], userText: true)
        var newPinyin = PinyinDictionary(rows: pinyinRows)
        struct Settings: Decodable { let mergePinyinIntoWubi: Bool? }
        let settingsURL = dataDirectory.appendingPathComponent("settings.json")
        var enabled = true
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            do { enabled = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: settingsURL)).mergePinyinIntoWubi ?? true }
            catch { problems.append("设置文件无效，使用默认设置：\(error.localizedDescription)") }
        }
        let original = WubiDictionary(rows: wubiRows)
        guard original.count > 0 else {
            issues = problems + ["没有有效的五笔词条，保留此前的运行时词库"]
            log("Wubi dictionaries: " + issues.joined(separator: "\n"))
            return false
        }
        let merged = enabled ? DictionaryMerger.merge(wubiRows: wubiRows, pinyin: newPinyin) : nil
        // Replace snapshots only after reading all sources; existing engine closures see the new data.
        wubi = merged?.dictionary ?? original
        newPinyin.discardMergeMetadata()
        pinyin = newPinyin
        report = merged?.report.summary()
        mergeEnabled = enabled
        do {
            if let fullReport = merged?.report { try fullReport.write(to: dataDirectory) }
            else {
                for file in ["dictionary-merge-report.json", "dictionary-merge-report.md"] {
                    let url = dataDirectory.appendingPathComponent(file)
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                }
            }
        } catch { problems.append("无法写入合并报告：\(error.localizedDescription)") }
        issues = problems
        do {
            try issues.joined(separator: "\n").write(to: dataDirectory.appendingPathComponent("dictionary-load-issues.log"), atomically: true, encoding: .utf8)
        } catch { log("Wubi dictionary log error: " + error.localizedDescription) }
        log("Wubi dictionaries: \(wubi.count) entries, Pinyin: \(pinyin.count), added: \(report?.addedPhrases ?? 0)")
        if !issues.isEmpty { log("Wubi dictionaries: " + issues.joined(separator: "\n")) }
        return true
    }
}
