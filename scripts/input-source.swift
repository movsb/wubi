import Cocoa
import Carbon

let identifier = "com.movsb.inputmethod.Wubi"
func fail(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(1)
}
func property(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let value = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
}
func sources() -> [TISInputSource] {
    TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
}
let arguments = CommandLine.arguments
guard arguments.count >= 2 else { fail("需要 stop、select 或 notify-success 参数") }
switch arguments[1] {
case "notify-success":
    let notification = Process()
    notification.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    notification.arguments = ["-e", "display notification \"最新版本已启动，可以继续输入。\" with title \"小桃的五笔重新加载成功\""]
    do {
        try notification.run()
        notification.waitUntilExit()
        if notification.terminationStatus != 0 {
            fputs("无法发送成功通知；输入法已重新加载。\n", stderr)
        }
    } catch {
        fputs("无法发送成功通知：\(error.localizedDescription)\n", stderr)
    }
case "stop":
    let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let original = property(current, kTISPropertyInputSourceID) else { fail("无法读取当前输入源") }
    if original == identifier {
        guard let fallback = sources().first(where: { property($0, kTISPropertyInputSourceType) == kTISTypeKeyboardLayout as String }),
              TISSelectInputSource(fallback) == noErr else { fail("无法切换到备用键盘，请先手动切换到其他输入法") }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
    }
    let applications = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
    for app in applications {
        // A background input method may not respond to an ordinary Quit request.
        guard app.forceTerminate() || app.isTerminated else { fail("无法停止小桃的五笔输入法进程") }
    }
    let deadline = Date(timeIntervalSinceNow: 5)
    while applications.contains(where: { !$0.isTerminated }) && Date() < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }
    guard applications.allSatisfy({ $0.isTerminated }) else { fail("输入法进程没有退出，停止更新") }
    print(original)
case "select":
    guard arguments.count == 3 else { fail("需要输入源 ID") }
    for _ in 0..<30 {
        if let source = sources().first(where: { property($0, kTISPropertyInputSourceID) == arguments[2] }),
           TISSelectInputSource(source) == noErr { exit(0) }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }
    fail("更新已完成，但无法恢复输入源，请从菜单栏手动选择「小桃的五笔」")
default: fail("未知命令")
}
