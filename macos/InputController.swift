import Cocoa
import InputMethodKit

@objc(WubiInputController)
class WubiInputController: IMKInputController {
    private static let dictionary: WubiDictionary = {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Bundle.main.resourceURL!, includingPropertiesForKeys: nil)) ?? []
        do { return try WubiDictionary(urls: urls.filter { $0.lastPathComponent.hasSuffix(".dict.yaml") }) }
        catch { NSLog("Wubi dictionary error: %@", String(describing: error)); return try! WubiDictionary(urls: []) }
    }()
    private lazy var engine = InputEngine(lookup: Self.dictionary.lookup)
    private var code: String { engine.code }
    private var page: Int { engine.page }
    private var choices: [String] { engine.choices }
    private var panel: NSPanel?
    private var hintDismissal: DispatchWorkItem?
    private let label = NSTextField(labelWithString: "")
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
        let menu = NSMenu(title: "五笔")
        menu.autoenablesItems = false
        let item = NSMenuItem(title: "重新构建并加载输入法", action: #selector(rebuildAndReload(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = reloadScript != nil && Self.reloadProcess == nil
        item.toolTip = "从本机源码构建并重启五笔，无需注销"
        menu.addItem(item)
        return menu
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

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? IMKTextInput, event.type == .keyDown else { return false }
        dismissQuoteHint()
        let result = engine.handle(InputKey(
            text: event.characters ?? "", code: event.keyCode,
            capsLock: event.modifierFlags.contains(.capsLock),
            shortcut: !event.modifierFlags.intersection([.command, .control, .option]).isEmpty))
        apply(result.effects, to: client)
        return result.handled
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
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
            case .quoteHint(let text):
                showQuoteHint(text, client: client)
            }
        }
    }

    private func refresh(_ client: IMKTextInput) {
        client.setMarkedText(code, selectionRange: NSRange(location: code.utf16.count, length: 0), replacementRange: missingRange)
        guard !code.isEmpty else { panel?.orderOut(nil); return }
        let values = choices
        guard !values.isEmpty else { panel?.orderOut(nil); return }
        let start = min(page * 9, values.count)
        let visible = values.dropFirst(start).prefix(9)
        let text = NSMutableAttributedString(string: "")
        let wordFont = NSFont.systemFont(ofSize: 13)
        let numberFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let wordAttributes: [NSAttributedString.Key: Any] = [
            .font: wordFont,
            .foregroundColor: NSColor.labelColor,
        ]
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .baselineOffset: (wordFont.ascender + wordFont.descender - numberFont.ascender - numberFont.descender) / 2,
        ]
        for (index, word) in visible.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "\n", attributes: wordAttributes)) }
            text.append(NSAttributedString(string: "\(index + 1) ", attributes: numberAttributes))
            var attributes = wordAttributes
            attributes[.foregroundColor] = start + index == engine.selectedIndex
                ? NSColor.labelColor : NSColor.secondaryLabelColor
            text.append(NSAttributedString(string: word, attributes: attributes))
        }
        present(text, client: client)
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
            .foregroundColor: NSColor.labelColor,
        ]), client: client)
        let dismissal = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
            self?.hintDismissal = nil
        }
        hintDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: dismissal)
    }

    private func present(_ text: NSAttributedString, client: IMKTextInput) {
        if panel == nil {
            let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.level = .popUpMenu
            window.hasShadow = true
            window.backgroundColor = .windowBackgroundColor
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.ignoresMouseEvents = true
            label.font = .systemFont(ofSize: 13)
            label.maximumNumberOfLines = 0
            window.contentView?.addSubview(label)
            panel = window
        }
        label.attributedStringValue = text
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Measure the current page, independent of the previous label frame.
        // Include the label's internal inset in addition to the window padding.
        let width = min(bounds.width, ceil(text.size().width) + 16)
        let measured = text.boundingRect(
            with: NSSize(width: max(1, width - 16), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = ceil(measured.height) + 8
        label.frame = NSRect(x: 6, y: 4, width: width - 12, height: height - 8)
        let x = min(max(rect.minX, bounds.minX), max(bounds.minX, bounds.maxX - width))
        let y = rect.minY - height - 4 < bounds.minY ? min(rect.maxY + 4, bounds.maxY - height) : rect.minY - height - 4
        panel?.setFrame(NSRect(x: x, y: max(bounds.minY, y), width: width, height: height), display: true)
        panel?.orderFrontRegardless()
    }
}
