import Foundation

final class DictionaryStore {
    static var defaultDataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wubi", isDirectory: true)
    }
    static let shared = DictionaryStore(resourceDirectory: Bundle.main.resourceURL!, dataDirectory: defaultDataDirectory)

    private let resourceDirectory: URL
    private let log: (String) -> Void
    let dataDirectory: URL
    private(set) var wubi = WubiDictionary(rows: [])
    private(set) var pinyin = PinyinDictionary(rows: [])
    private(set) var report: DictionaryMergeReport?
    private(set) var issues: [String] = []
    private(set) var mergeEnabled = true

    init(resourceDirectory: URL, dataDirectory: URL, log: @escaping (String) -> Void = { NSLog("%@", $0) }) {
        self.resourceDirectory = resourceDirectory
        self.dataDirectory = dataDirectory
        self.log = log
        reload()
    }

    @discardableResult
    func reload() -> Bool {
        var problems: [String] = []
        let userWubi = dataDirectory.appendingPathComponent("Dictionaries/Wubi", isDirectory: true)
        let userPinyin = dataDirectory.appendingPathComponent("Dictionaries/Pinyin", isDirectory: true)
        for directory in [userWubi, userPinyin] {
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch { problems.append("无法创建词库目录：\(error.localizedDescription)") }
        }
        func files(_ directory: URL) -> [URL] {
            do {
                return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasSuffix(".dict.yaml") }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
            } catch {
                problems.append("无法读取 \(directory.path)：\(error.localizedDescription)")
                return []
            }
        }
        func rows(_ urls: [URL]) -> [DictionaryRow] {
            urls.flatMap { url -> [DictionaryRow] in
                do { return try DictionaryRow.read(url) }
                catch {
                    problems.append("跳过 \(url.path)：\(error.localizedDescription)")
                    return []
                }
            }
        }
        let bundled = files(resourceDirectory)
        let wubiRows = rows(bundled.filter { !["pinyin_simp.dict.yaml", "wubi_merged.dict.yaml"].contains($0.lastPathComponent) })
            + rows(files(userWubi))
        let pinyinRows = rows(bundled.filter { $0.lastPathComponent == "pinyin_simp.dict.yaml" }) + rows(files(userPinyin))
        let newPinyin = PinyinDictionary(rows: pinyinRows)
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
        pinyin = newPinyin
        report = merged?.report
        mergeEnabled = enabled
        do {
            if let report { try report.write(to: dataDirectory) }
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
