import Cocoa
import InputMethodKit

@objc(WubiInputController)
class WubiInputController: IMKInputController {
    private static let dictionary: WubiDictionary = {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Bundle.main.resourceURL!, includingPropertiesForKeys: nil)) ?? []
        do { return try WubiDictionary(urls: urls.filter { $0.lastPathComponent.hasSuffix(".dict.yaml") }) }
        catch { NSLog("Wubi dictionary error: %@", String(describing: error)); return try! WubiDictionary(urls: []) }
    }()
    private var code = ""
    private var page = 0
    private var choices: [String] { Self.dictionary.lookup(code) }
    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private let missingRange = NSRange(location: NSNotFound, length: 0)

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? IMKTextInput, event.type == .keyDown else { return false }
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if !code.isEmpty { commitComposition(sender) }
            return false
        }
        let text = event.characters ?? ""
        if text.utf8.count == 1, let byte = text.utf8.first, (97...122).contains(byte), !event.modifierFlags.contains(.capsLock) {
            if code.count == 4 { commitComposition(sender) }
            code += text
            page = 0
            refresh(client)
            return true
        }
        guard !code.isEmpty else { return false }
        switch event.keyCode {
        case 53: clear(client)
        case 51:
            code.removeLast(); page = 0; refresh(client)
        case 36, 76: insert(code, client)
        case 49: commitComposition(sender)
        case 123, 126, 116: page = max(0, page - 1); refresh(client)
        case 124, 125, 121: page = min(max(0, (choices.count - 1) / 9), page + 1); refresh(client)
        default:
            if let digit = Int(text), (1...9).contains(digit) {
                let index = page * 9 + digit - 1
                if choices.indices.contains(index) { insert(choices[index], client) }
            } else if text == "-" || text == "=" {
                page = min(max(0, (choices.count - 1) / 9), max(0, page + (text == "=" ? 1 : -1)))
                refresh(client)
            } else {
                commitComposition(sender)
                return false
            }
        }
        return true
    }

    override func commitComposition(_ sender: Any!) {
        guard !code.isEmpty, let client = sender as? IMKTextInput else { return }
        let values = choices
        insert(values.isEmpty ? code : values[min(page * 9, values.count - 1)], client)
    }

    override func deactivateServer(_ sender: Any!) {
        commitComposition(sender)
        panel?.orderOut(nil)
        super.deactivateServer(sender)
    }

    private func insert(_ text: String, _ client: IMKTextInput) {
        code = ""; page = 0
        client.insertText(text, replacementRange: missingRange)
        panel?.orderOut(nil)
    }

    private func clear(_ client: IMKTextInput) {
        code = ""; page = 0
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: missingRange)
        panel?.orderOut(nil)
    }

    private func refresh(_ client: IMKTextInput) {
        client.setMarkedText(code, selectionRange: NSRange(location: code.utf16.count, length: 0), replacementRange: missingRange)
        guard !code.isEmpty else { panel?.orderOut(nil); return }
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 70), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.level = .popUpMenu
            window.hasShadow = true
            window.backgroundColor = .windowBackgroundColor
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.ignoresMouseEvents = true
            label.font = .systemFont(ofSize: 16)
            label.maximumNumberOfLines = 0
            window.contentView?.addSubview(label)
            panel = window
        }
        let values = choices
        let start = min(page * 9, values.count)
        let visible = values.dropFirst(start).prefix(9)
        label.stringValue = code + "   \(page + 1)/\(max(1, (values.count + 8) / 9))\n" + (values.isEmpty ? "无候选词 · 回车输入编码" : visible.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        let width = min(720, max(280, label.intrinsicContentSize.width + 24))
        let height = max(72, label.intrinsicContentSize.height + 20)
        label.frame = NSRect(x: 12, y: 10, width: width - 24, height: height - 20)
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(max(rect.minX, bounds.minX), max(bounds.minX, bounds.maxX - width))
        let y = rect.minY - height - 4 < bounds.minY ? min(rect.maxY + 4, bounds.maxY - height) : rect.minY - height - 4
        panel?.setFrame(NSRect(x: x, y: max(bounds.minY, y), width: width, height: height), display: true)
        panel?.orderFrontRegardless()
    }
}
