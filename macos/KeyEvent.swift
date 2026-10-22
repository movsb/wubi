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
