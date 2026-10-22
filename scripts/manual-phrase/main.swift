import Cocoa

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let arguments = CommandLine.arguments
guard arguments.count == 4 else { exit(1) }
let snapshot = URL(fileURLWithPath: arguments[1])
do {
    let index = try CandidateIndex(mappedURL: snapshot)
    // The mapping remains valid after unlink, including while the input method reloads.
    try FileManager.default.removeItem(at: snapshot)
    let window = ManualPhraseWindow(readingIndex: index,
        dataDirectory: URL(fileURLWithPath: arguments[2]),
        previousApp: Int32(arguments[3]).flatMap { NSRunningApplication(processIdentifier: $0) })
    window.show()
    application.run()
    withExtendedLifetime(window) {}
} catch {
    try? FileManager.default.removeItem(at: snapshot)
    let alert = NSAlert()
    alert.messageText = "无法打开手动造词"
    alert.informativeText = error.localizedDescription
    alert.runModal()
    exit(1)
}
