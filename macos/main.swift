import Cocoa
import InputMethodKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
_ = DictionaryStore.shared
let server = IMKServer(name: "MovsbWubiConnection", bundleIdentifier: Bundle.main.bundleIdentifier!)!
application.run()
withExtendedLifetime(server) {}
