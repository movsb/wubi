import Cocoa

final class ManualPhraseWindow: NSObject, NSWindowDelegate, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 290),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 324, height: 38))
    private let choices = NSTableView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var readings: ManualReadings?
    private var word = ""
    private let readingIndex: CandidateIndex
    private let dataDirectory: URL
    private let previousApp: NSRunningApplication?

    init(readingIndex: CandidateIndex, dataDirectory: URL, previousApp: NSRunningApplication?) {
        self.readingIndex = readingIndex
        self.dataDirectory = dataDirectory
        self.previousApp = previousApp
        super.init()
        window.title = "手动造词"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.hidesOnDeactivate = false
        let content = window.contentView!
        let title = NSTextField(labelWithString: "输入汉字词语，双击下方拼音保存")
        title.frame = NSRect(x: 18, y: 252, width: 324, height: 22)
        title.alignment = .center
        content.addSubview(title)
        let scroll = NSScrollView(frame: NSRect(x: 18, y: 208, width: 324, height: 38))
        scroll.borderType = .bezelBorder
        scroll.documentView = editor
        editor.font = .systemFont(ofSize: 18)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        editor.defaultParagraphStyle = paragraph
        editor.alignment = .left
        editor.delegate = self
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        let lineHeight = editor.layoutManager!.defaultLineHeight(for: editor.font!)
        editor.textContainerInset = NSSize(width: 6,
            height: max(0, (scroll.contentSize.height - lineHeight) / 2))
        editor.isVerticallyResizable = false
        editor.isHorizontallyResizable = true
        editor.minSize = scroll.contentSize
        editor.maxSize = NSSize(width: .greatestFiniteMagnitude, height: scroll.contentSize.height)
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: .greatestFiniteMagnitude, height: scroll.contentSize.height)
        editor.textContainer?.maximumNumberOfLines = 1
        editor.textContainer?.lineBreakMode = .byClipping
        content.addSubview(scroll)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pinyin"))
        column.title = "可用拼音"
        column.width = 302
        choices.addTableColumn(column)
        choices.headerView = nil
        choices.rowHeight = 28
        choices.allowsMultipleSelection = false
        choices.dataSource = self
        choices.delegate = self
        choices.target = self
        choices.doubleAction = #selector(saveChoice(_:))
        let readingScroll = NSScrollView(frame: NSRect(x: 18, y: 58, width: 324, height: 140))
        readingScroll.borderType = .bezelBorder
        readingScroll.hasVerticalScroller = true
        readingScroll.documentView = choices
        content.addSubview(readingScroll)
        status.frame = NSRect(x: 18, y: 12, width: 324, height: 36)
        status.font = .systemFont(ofSize: 12)
        status.alignment = .center
        content.addSubview(status)
    }

    func show() {
        if window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        editor.string = ""
        readings = nil
        word = ""
        choices.reloadData()
        status.stringValue = "输入或粘贴汉字，双击拼音保存\n五笔编码会自动生成"
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let bounds = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: bounds.midX - window.frame.width / 2,
                                          y: bounds.midY - window.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
    }

    func textDidChange(_ notification: Notification) { updateReadings() }

    private func updateReadings() {
        // Only committed characters participate; preedit letters are still being composed.
        let committed = NSMutableString(string: editor.string)
        let marked = editor.markedRange()
        if marked.location != NSNotFound, NSMaxRange(marked) <= committed.length {
            committed.deleteCharacters(in: marked)
        }
        let current = (committed as String).trimmingCharacters(in: .whitespacesAndNewlines)
        guard current != word else { return }
        word = current
        readings = nil
        if current.isEmpty {
            status.stringValue = "输入或粘贴汉字，双击拼音保存\n五笔编码会自动生成"
        } else {
            do {
                readings = try ManualReadings(word: current, readings: { self.readingIndex.lookup(String($0)) })
                status.stringValue = "共 \(readings!.count) 种拼音，双击一项保存\n五笔编码会自动生成"
            } catch { status.stringValue = error.localizedDescription }
        }
        choices.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { readings?.count ?? 0 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("reading")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        if cell.textField == nil {
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 14)
            label.frame = NSRect(x: 8, y: 4, width: tableColumn?.width ?? 302, height: 20)
            label.autoresizingMask = [.width]
            cell.addSubview(label)
            cell.textField = label
        }
        cell.textField?.stringValue = readings?.spelling(at: row) ?? ""
        return cell
    }

    @objc private func saveChoice(_ sender: NSTableView) {
        guard sender.clickedRow >= 0 else { return }
        save(index: sender.clickedRow)
    }

    private func save(index: Int) {
        guard let spelling = readings?.spelling(at: index) else { return }
        guard !editor.hasMarkedText(), editor.string.trimmingCharacters(in: .whitespacesAndNewlines) == word else {
            updateReadings()
            window.makeFirstResponder(editor)
            status.stringValue = "请先完成正在输入的汉字，再双击拼音保存"
            return
        }
        do {
            try ManualReadings.save(word: word, spelling: spelling,
                to: dataDirectory.appendingPathComponent("manual.txt"))
            DistributedNotificationCenter.default().postNotificationName(manualPhraseSavedNotification,
                object: nil, userInfo: nil, deliverImmediately: true)
            window.close()
        } catch { status.stringValue = error.localizedDescription }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        guard let replacementString, replacementString.rangeOfCharacter(from: .newlines) != nil else { return true }
        let singleLine = replacementString.components(separatedBy: .newlines).joined()
        if !singleLine.isEmpty {
            textView.insertText(singleLine, replacementRange: affectedCharRange)
        }
        return false
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:))
            || commandSelector == #selector(NSResponder.insertLineBreak(_:))
            || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            window.close()
            return true
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        previousApp?.activate(options: [])
        NSApp.terminate(nil)
    }
}
