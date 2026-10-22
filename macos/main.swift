import Cocoa
import InputMethodKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
_ = DictionaryStore.shared
let server = IMKServer(name: "MovsbWubiConnection", bundleIdentifier: Bundle.main.bundleIdentifier!)!
let manualPhraseObserver = DistributedNotificationCenter.default().addObserver(
    forName: manualPhraseSavedNotification, object: nil, queue: .main) { _ in
        if !DictionaryStore.shared.reload() { NSLog("手动造词已保存，但词库重新加载失败") }
    }
application.run()
withExtendedLifetime(server) {}
