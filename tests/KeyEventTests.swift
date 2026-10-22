import Cocoa
import IOKit.hidsystem

func runKeyEventTests() {
    func event(_ type: NSEvent.EventType, key: UInt16, flags: NSEvent.ModifierFlags = [], text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                        windowNumber: 0, context: nil, characters: text,
                        charactersIgnoringModifiers: text, isARepeat: false, keyCode: key)!
    }
    let down = InputKey(event: event(.flagsChanged, key: 56, flags: .shift))
    let up = InputKey(event: event(.flagsChanged, key: 56))
    check(down.isModifierChange && down.text.isEmpty && down.leftShiftDown,
          "real Shift-down NSEvent converts safely without device-specific flags")
    check(up.isModifierChange && up.text.isEmpty && !up.leftShiftDown,
          "real Shift-up NSEvent converts safely without reading characters")
    var engine = InputEngine { _ in [] }
    _ = engine.handle(down)
    let toggled = engine.handle(up)
    check(engine.englishMode && toggled.handled && toggled.effects == [.modeHint("英")],
          "real NSEvent Shift tap reaches engine and switches to English")
    let duplicateRelease = engine.handle(up)
    check(engine.englishMode && duplicateRelease.effects.isEmpty,
          "duplicate modifier release does not change mode or emit UI effects")
    check(engine.commit().isEmpty, "empty commit following mode switch has no effects")
    let letter = InputKey(event: event(.keyDown, key: 12, text: "q"))
    check(letter.text == "q" && !engine.handle(letter).handled && engine.code.isEmpty,
          "real letter event goes directly to client in English mode")

    let physicalFlags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | UInt(NX_DEVICELSHIFTKEYMASK))
    let physicalDown = InputKey(event: event(.flagsChanged, key: 56, flags: physicalFlags))
    check(physicalDown.leftShiftDown && !physicalDown.otherModifier, "device-specific left Shift flags also work")
    _ = engine.handle(physicalDown)
    let chinese = engine.handle(up)
    check(!engine.englishMode && chinese.handled && chinese.effects == [.modeHint("中")],
          "physical Shift tap switches back to Chinese and consumes release")
    _ = engine.handle(InputKey(event: event(.flagsChanged, key: 60, flags: .shift)))
    _ = engine.handle(InputKey(event: event(.flagsChanged, key: 60)))
    check(!engine.englishMode, "real right Shift events do not toggle")
    _ = engine.handle(down)
    let uppercase = InputKey(event: event(.keyDown, key: 0, flags: .shift, text: "A"))
    _ = engine.handle(uppercase)
    _ = engine.handle(up)
    check(!engine.englishMode && engine.code == "A", "real Shift-letter chord preserves Chinese mode")
    let shortcut = InputKey(event: event(.keyDown, key: 8, flags: .command, text: "c"))
    check(shortcut.shortcut && shortcut.text == "c", "real Command event preserves shortcut flag")
    print("PASS: native NSEvent conversion and Shift switching regressions")
}
