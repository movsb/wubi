import Cocoa

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let previousApp = NSWorkspace.shared.frontmostApplication
let temporary = URL(fileURLWithPath: CommandLine.arguments[1])
let index = CandidateIndex(items: [
    .init(text: "zhong", code: "重", weight: 10, order: 0),
    .init(text: "chong", code: "重", weight: 5, order: 1),
    .init(text: "xing", code: "行", weight: 10, order: 2),
    .init(text: "hang", code: "行", weight: 5, order: 3),
], rankExactByWeight: true)
let controller = ManualPhraseWindow(readingIndex: index, dataDirectory: temporary, previousApp: previousApp)
controller.show()
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    let window = app.windows.first { $0.title == "手动造词" }!
    let views = descendants(window.contentView!)
    let editor = views.compactMap { $0 as? NSTextView }.first!
    let table = views.compactMap { $0 as? NSTableView }.first!
    require(type(of: editor) == NSTextView.self, "uses an ordinary system text view")
    require(window.isKeyWindow && window.firstResponder === editor, "window focuses the text editor")
    require(editor.inputContext != nil, "native system input context exists")
    require(window.childWindows == nil || window.childWindows!.isEmpty, "no custom input candidate panel")
    editor.insertText("重", replacementRange: NSRange(location: NSNotFound, length: 0))
    require(table.numberOfRows == 2, "committing a character immediately updates readings")
    editor.setMarkedText("f", selectedRange: NSRange(location: 1, length: 0),
                         replacementRange: NSRange(location: NSNotFound, length: 0))
    require(table.numberOfRows == 2, "unconfirmed input does not enter pronunciation list")
    editor.insertText("行", replacementRange: NSRange(location: NSNotFound, length: 0))
    require(table.numberOfRows == 4, "confirming marked text updates polyphonic combinations")
    editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
    editor.delete(nil)
    require(table.numberOfRows == 0, "deleting text immediately clears readings")
    editor.insertNewline(nil)
    require(editor.string.isEmpty, "Return cannot insert a newline")
    editor.insertLineBreak(nil)
    require(editor.string.isEmpty, "line break commands cannot insert a newline")
    editor.insertText("重\r\n行\u{2028}", replacementRange: NSRange(location: NSNotFound, length: 0))
    require(editor.string == "重行" && table.numberOfRows == 4, "multiline paste becomes one line and updates readings")
    require(editor.textContainer?.maximumNumberOfLines == 1 && editor.isHorizontallyResizable,
            "long phrases stay on a horizontally scrolling line")
    editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
    editor.delete(nil)
    print("PASS: native editor focus, live readings and single-line input/paste")
    editor.insertText("重行", replacementRange: NSRange(location: NSNotFound, length: 0))
    window.makeFirstResponder(table)
    let point = table.convert(NSPoint(x: 30, y: table.rect(ofRow: 0).midY), to: nil)
    let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!
    let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 2, clickCount: 2, pressure: 0)!
    // NSTableView tracks the matching mouse-up before dispatching its doubleAction.
    app.postEvent(up, atStart: true)
    table.mouseDown(with: down)
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        fatalError("double-click must save, close the window and exit the helper")
    }
}
app.run()
