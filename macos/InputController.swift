import Cocoa
import InputMethodKit

private enum CandidateColors {
    static let primary = NSColor(name: NSColor.Name("WubiPrimary")) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.78, alpha: 1) : .labelColor
    }
    static let secondary = NSColor(name: NSColor.Name("WubiSecondary")) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.50, alpha: 1) : .secondaryLabelColor
    }
}

private final class CandidateBackgroundView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        // CGColor is a snapshot: resolve it again whenever the system appearance changes.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        subviews.forEach { $0.needsDisplay = true }
    }
}

// Use the same text layout for drawing and hit testing, including wrapped candidates.
private final class CandidateLabel: NSView {
    static let candidateWord = NSAttributedString.Key("WubiCandidateWord")
    var onDelete: ((String) -> Void)?
    private let storage = NSTextStorage()
    private let layout = NSLayoutManager()
    private let container = NSTextContainer(size: .zero)
    var attributedStringValue = NSAttributedString(string: "") {
        didSet { storage.setAttributedString(attributedStringValue); needsDisplay = true }
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func prepareLayout() {
        container.containerSize = NSSize(width: max(1, bounds.width - 4), height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
    }
    override func draw(_ dirtyRect: NSRect) {
        prepareLayout()
        let glyphs = layout.glyphRange(for: container)
        layout.drawBackground(forGlyphRange: glyphs, at: NSPoint(x: 2, y: 0))
        layout.drawGlyphs(forGlyphRange: glyphs, at: NSPoint(x: 2, y: 0))
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        prepareLayout()
        let point = convert(event.locationInWindow, from: nil)
        let location = NSPoint(x: point.x - 2, y: point.y)
        guard storage.length > 0, layout.usedRect(for: container).contains(location) else { return nil }
        let glyph = layout.glyphIndex(for: location, in: container)
        guard NSLocationInRange(glyph, layout.glyphRange(for: container)) else { return nil }
        let character = layout.characterIndexForGlyph(at: glyph)
        guard let word = storage.attribute(Self.candidateWord, at: character, effectiveRange: nil) as? String else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: "删除此词条", action: #selector(deleteCandidate(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = word
        menu.addItem(item)
        return menu
    }
    @objc private func deleteCandidate(_ sender: NSMenuItem) {
        guard let word = sender.representedObject as? String else { return }
        onDelete?(word)
    }
}

@objc(WubiInputController)
class WubiInputController: IMKInputController {
    private lazy var engine = InputEngine(
        lookup: { DictionaryStore.shared.wubi.lookup($0) },
        pinyinLookup: { DictionaryStore.shared.pinyin.lookup($0) },
        wubiCandidates: { DictionaryStore.shared.wubi.candidates(prefix: $0) },
        pinyinCandidates: { DictionaryStore.shared.pinyin.candidates(prefix: $0) },
        usage: WordUsageStore.shared)
    private var code: String { engine.code }
    private var page: Int { engine.page }
    private static var manualApplication: NSRunningApplication?
    private static var launchingManualApplication = false
    private var panel: NSPanel?
    private var hintDismissal: DispatchWorkItem?
    private let label = CandidateLabel(frame: .zero)
    private let missingRange = NSRange(location: NSNotFound, length: 0)
    private static var reloadProcess: Process?

    private var reloadScript: URL? {
        guard let location = Bundle.main.url(forResource: "DevelopmentSourcePath", withExtension: "txt"),
              let path = try? String(contentsOf: location, encoding: .utf8) else { return nil }
        let script = URL(fileURLWithPath: path.trimmingCharacters(in: .newlines))
            .appendingPathComponent("scripts/reload-macos.sh")
        return FileManager.default.isExecutableFile(atPath: script.path) ? script : nil
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "桃酥")
        menu.autoenablesItems = false
        let item = NSMenuItem(title: "重新构建并加载输入法", action: #selector(rebuildAndReload(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = reloadScript != nil && Self.reloadProcess == nil
        item.toolTip = "从本机源码构建并重启桃酥，无需注销"
        menu.addItem(item)
        let manual = NSMenuItem(title: "手动造词", action: #selector(startManualPhrase(_:)), keyEquivalent: "")
        manual.target = self
        menu.addItem(manual)
        let reload = NSMenuItem(title: "重新加载词库", action: #selector(reloadDictionaries(_:)), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)
        let open = NSMenuItem(title: "打开用户词库目录", action: #selector(openDictionaryDirectory(_:)), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        return menu
    }

    @objc private func startManualPhrase(_ sender: Any?) {
        if let app = Self.manualApplication, !app.isTerminated {
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }
        guard !Self.launchingManualApplication else { return }
        if let currentClient: IMKTextInput = client() { commitComposition(currentClient) }
        panel?.orderOut(nil)
        let snapshot = FileManager.default.temporaryDirectory.appendingPathComponent("Wubi-readings-" + UUID().uuidString)
        do {
            try DictionaryStore.shared.pinyin.writeReadings(to: snapshot)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = [snapshot.path, DictionaryStore.shared.dataDirectory.path,
                String(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)]
            Self.launchingManualApplication = true
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ManualPhrase.app")
            NSWorkspace.shared.openApplication(at: helper, configuration: configuration) { app, error in
                DispatchQueue.main.async {
                    Self.launchingManualApplication = false
                    Self.manualApplication = app
                    if let error {
                        try? FileManager.default.removeItem(at: snapshot)
                        let alert = NSAlert()
                        alert.messageText = "无法打开手动造词"
                        alert.informativeText = error.localizedDescription
                        alert.runModal()
                    }
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: snapshot)
            let alert = NSAlert()
            alert.messageText = "无法打开手动造词"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func reloadDictionaries(_ sender: Any?) {
        let currentClient: IMKTextInput? = client()
        if let currentClient { commitComposition(currentClient) }
        let success = DictionaryStore.shared.reload()
        let message = !success ? "词库加载失败，保留旧词库" :
            (DictionaryStore.shared.issues.isEmpty ? "词库已更新" : "词库已更新，部分文件有误")
        let notification = Process()
        notification.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // Pass text as arguments, independently of the focused input client.
        notification.arguments = ["-e", """
            on run argv
                display notification (item 1 of argv) with title "桃酥词库"
            end run
            """, message]
        notification.standardOutput = FileHandle.nullDevice
        notification.terminationHandler = { task in
            if task.terminationStatus != 0 { NSLog("无法发送词库更新通知：退出码 %d", task.terminationStatus) }
        }
        do { try notification.run() }
        catch { NSLog("无法发送词库更新通知：%@", error.localizedDescription) }
    }

    @objc private func openDictionaryDirectory(_ sender: Any?) {
        NSWorkspace.shared.open(DictionaryStore.shared.dataDirectory)
    }

    @objc private func rebuildAndReload(_ sender: Any?) {
        guard Self.reloadProcess == nil, let script = reloadScript else { return }
        do {
            let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Wubi", isDirectory: true)
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let log = logs.appendingPathComponent("reload.log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let output = try FileHandle(forWritingTo: log)
            let process = Process()
            // The external updater must survive termination of this input-method process.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            process.arguments = ["/bin/bash", script.path, "--notify-success"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = output
            process.terminationHandler = { task in
                DispatchQueue.main.async {
                    Self.reloadProcess = nil
                    if task.terminationStatus != 0 {
                        let alert = NSAlert()
                        alert.messageText = "输入法更新失败"
                        alert.informativeText = "请查看日志：\(log.path)"
                        alert.runModal()
                    }
                }
            }
            try process.run()
            Self.reloadProcess = process
            try? output.close()
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法启动输入法更新"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.union(.flagsChanged).rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? IMKTextInput,
              event.type == .keyDown || event.type == .flagsChanged else { return false }
        // Modifier notifications can follow the Shift release that shows the mode hint.
        if event.type == .keyDown { dismissQuoteHint() }
        let result = engine.handle(InputKey(event: event))
        apply(result.effects, to: client)
        return result.handled
    }

    override func commitComposition(_ sender: Any!) {
        // InputMethodKit may request a commit after a mode switch even with no preedit.
        // That is not new input and must not dismiss the just-shown hint.
        guard !code.isEmpty, let client = sender as? IMKTextInput else { return }
        dismissQuoteHint()
        apply(engine.commit(), to: client)
    }

    override func deactivateServer(_ sender: Any!) {
        dismissQuoteHint()
        let effects = engine.deactivate()
        if let client = sender as? IMKTextInput { apply(effects, to: client) }
        panel?.orderOut(nil)
        super.deactivateServer(sender)
    }

    private func apply(_ effects: [InputEffect], to client: IMKTextInput) {
        for effect in effects {
            switch effect {
            case .insert(let text):
                client.insertText(text, replacementRange: missingRange)
                panel?.orderOut(nil)
            case .refresh:
                refresh(client)
            case .quoteHint(let text), .modeHint(let text):
                showQuoteHint(text, client: client)
            }
        }
    }

    private func refresh(_ client: IMKTextInput) {
        client.setMarkedText(code, selectionRange: NSRange(location: code.utf16.count, length: 0), replacementRange: missingRange)
        guard !code.isEmpty else { panel?.orderOut(nil); return }
        let values = engine.candidates
        guard !values.isEmpty else { panel?.orderOut(nil); return }
        let start = min(page * InputEngine.pageSize, values.count)
        let visible = values.dropFirst(start).prefix(InputEngine.pageSize)
        let text = NSMutableAttributedString(string: "")
        let wordFont = NSFont.systemFont(ofSize: 13)
        let numberFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        let wordAttributes: [NSAttributedString.Key: Any] = [
            .font: wordFont,
            .foregroundColor: CandidateColors.primary,
            .paragraphStyle: paragraphStyle,
        ]
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: CandidateColors.secondary,
            .paragraphStyle: paragraphStyle,
            .baselineOffset: (wordFont.ascender + wordFont.descender - numberFont.ascender - numberFont.descender) / 2,
        ]
        var leftWidth: CGFloat = 0
        var remainingWidth: CGFloat = 0
        for (index, candidate) in visible.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "\n", attributes: wordAttributes)) }
            let rowStart = text.length
            let number = NSAttributedString(string: "\(index + 1) ", attributes: numberAttributes)
            text.append(number)
            var attributes = wordAttributes
            attributes[.foregroundColor] = start + index == engine.selectedIndex
                ? CandidateColors.primary : CandidateColors.secondary
            let word = NSAttributedString(string: candidate.text, attributes: attributes)
            text.append(word)
            leftWidth = max(leftWidth, number.size().width + word.size().width)
            let annotation = engine.pinyinMode
                ? DictionaryStore.shared.wubi.reverseLookup(candidate.text) ?? ""
                : candidate.remainingCode
            if !annotation.isEmpty {
                let remaining = NSAttributedString(string: annotation, attributes: numberAttributes)
                text.append(NSAttributedString(string: "\t", attributes: numberAttributes))
                text.append(remaining)
                remainingWidth = max(remainingWidth, remaining.size().width)
            }
            text.addAttribute(CandidateLabel.candidateWord, value: candidate.text,
                              range: NSRange(location: rowStart, length: text.length - rowStart))
        }
        let contentWidth = ceil(leftWidth + (remainingWidth > 0 ? 12 + remainingWidth : 0))
        present(text, client: client, contentWidth: contentWidth)
    }

    private func deleteCandidate(_ word: String) {
        guard let currentClient: IMKTextInput = client(), !code.isEmpty else { return }
        do {
            try DictionaryRow.exclude(word, at: DictionaryStore.shared.dataDirectory.appendingPathComponent("excluded.txt"))
            guard DictionaryStore.shared.reload() else {
                throw NSError(domain: "Wubi.Dictionary", code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "排除词条已保存，但词库重新加载失败"])
            }
            engine.refreshCandidates()
            refresh(currentClient)
        } catch {
            NSLog("删除词条失败：%@", error.localizedDescription)
            showQuoteHint("删除词条失败", client: currentClient)
        }
    }

    private func dismissQuoteHint() {
        guard let dismissal = hintDismissal else { return }
        dismissal.cancel()
        hintDismissal = nil
        panel?.orderOut(nil)
    }

    private func showQuoteHint(_ message: String, client: IMKTextInput) {
        dismissQuoteHint()
        present(NSAttributedString(string: message, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: CandidateColors.primary,
        ]), client: client)
        let dismissal = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
            self?.hintDismissal = nil
        }
        hintDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: dismissal)
    }

    private func present(_ text: NSAttributedString, client: IMKTextInput, contentWidth: CGFloat? = nil) {
        if panel == nil {
            let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.hasShadow = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = CandidateBackgroundView(frame: .zero)
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.masksToBounds = true
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.ignoresMouseEvents = false
            label.onDelete = { [weak self] word in self?.deleteCandidate(word) }
            window.contentView?.addSubview(label)
            panel = window
        }
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        // Candidate panels may overlap the Dock to stay close to the insertion point.
        let bounds = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Measure the current page, independent of the previous label frame.
        // Include the label's internal inset in addition to the window padding.
        let width = min(bounds.width, ceil(contentWidth ?? text.size().width) + 16)
        let rendered = NSMutableAttributedString(attributedString: text)
        if contentWidth != nil, text.length > 0 {
            let style = (text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            style.tabStops = [NSTextTab(textAlignment: .right, location: max(1, width - 16), options: [:])]
            rendered.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: rendered.length))
        }
        label.attributedStringValue = rendered
        let measured = rendered.boundingRect(
            with: NSSize(width: max(1, width - 16), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = ceil(measured.height) + 8
        label.frame = NSRect(x: 6, y: 4, width: width - 12, height: height - 8)
        let x = min(max(rect.minX, bounds.minX), max(bounds.minX, bounds.maxX - width))
        let y = rect.minY - height - 4 < bounds.minY ? min(rect.maxY + 4, bounds.maxY - height) : rect.minY - height - 4
        panel?.setFrame(NSRect(x: x, y: max(bounds.minY, y), width: width, height: height), display: true)
        // Input clients such as launchers can sit above the normal popup level.
        // Recompute for each presentation so switching clients also lowers it again.
        panel?.level = NSWindow.Level(rawValue: max(NSWindow.Level.popUpMenu.rawValue, Int(client.windowLevel()) + 1))
        panel?.orderFrontRegardless()
    }
}
