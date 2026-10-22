import Cocoa
import InputMethodKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let server = IMKServer(name: "MovsbWubiConnection", bundleIdentifier: Bundle.main.bundleIdentifier!)!
application.run()
withExtendedLifetime(server) {}
