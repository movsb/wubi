import Cocoa
import IOKit.hidsystem

extension InputKey {
    init(event: NSEvent) {
        let flags = event.modifierFlags
        let leftMask = UInt(NX_DEVICELSHIFTKEYMASK)
        let rightMask = UInt(NX_DEVICERSHIFTKEYMASK)
        let hasSideFlags = flags.rawValue & (leftMask | rightMask) != 0
        self.init(
            // Reading characters on flagsChanged raises an AppKit exception.
            text: event.type == .keyDown ? event.characters ?? "" : "",
            code: event.keyCode,
            capsLock: flags.contains(.capsLock),
            shortcut: !flags.intersection([.command, .control, .option]).isEmpty,
            isModifierChange: event.type == .flagsChanged,
            leftShiftDown: hasSideFlags ? flags.rawValue & leftMask != 0
                : event.keyCode == 56 && flags.contains(.shift),
            rightShiftDown: hasSideFlags ? flags.rawValue & rightMask != 0
                : event.keyCode == 60 && flags.contains(.shift),
            otherModifier: flags.contains(.function))
    }
}

// Some clients bind commands to key-up. Swallow the matching release even when
// the key-down (notably Escape) has just closed the private editor.
struct ManualKeyReleases {
    private var consumed = Set<UInt16>()
    mutating func record(key: UInt16, handled: Bool, wasEditing: Bool, isEditing: Bool) {
        if handled && (wasEditing || isEditing) { consumed.insert(key) }
    }
    mutating func consume(key: UInt16) -> Bool { consumed.remove(key) != nil }
    mutating func reset() { consumed.removeAll() }
}
