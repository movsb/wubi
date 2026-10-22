import Cocoa
import Carbon
import Darwin

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
@main
enum InputSourceTool {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else { fail("需要 current、stop、select 或通知参数") }
        switch arguments[1] {
        case "current":
            let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            guard let value = property(current, kTISPropertyInputSourceID) else { fail("无法读取当前输入源") }
            print(value)
        case "register":
            guard arguments.count == 3 else { fail("需要输入法 app 路径") }
            let url = URL(fileURLWithPath: arguments[2])
            guard TISRegisterInputSource(url as CFURL) == noErr else { fail("无法注册更新后的输入法") }
        case "notify-success", "notify-failure":
            let notification = Process()
            notification.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            notification.arguments = arguments[1] == "notify-success"
                ? ["-e", "display notification \"最新版本已启动，可以继续输入。\" with title \"桃酥重新加载成功\""]
                : ["-e", "display notification \"请查看 ~/Library/Logs/Wubi/reload.log，更新流程已尝试恢复原输入法。\" with title \"桃酥重新加载失败\""]
            do {
                try notification.run()
                notification.waitUntilExit()
                if notification.terminationStatus != 0 {
                    fputs("无法发送重新加载结果通知。\n", stderr)
                }
            } catch {
                fputs("无法发送重新加载结果通知：\(error.localizedDescription)\n", stderr)
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
            let pids = applications.map(\.processIdentifier)
            for app in applications {
                // Stop this known input-method PID directly, without AppKit lifecycle caching.
                guard kill(app.processIdentifier, SIGTERM) == 0 || errno == ESRCH else {
                    _ = TISSelectInputSource(current)
                    fail("无法停止桃酥输入法进程")
                }
            }
            // NSRunningApplication.isTerminated can remain stale in a command-line helper.
            // Check the actual PID instead of waiting on that cached AppKit property.
            guard ProcessLifecycle.waitForExit(pids, timeout: 5) else {
                _ = TISSelectInputSource(current)
                fail("输入法进程没有退出，停止更新并恢复原输入源")
            }
            print(original)
        case "select":
            guard arguments.count == 3 else { fail("需要输入源 ID") }
            for _ in 0..<50 {
                if let source = sources().first(where: { property($0, kTISPropertyInputSourceID) == arguments[2] }),
                   TISSelectInputSource(source) == noErr {
                    let selected = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
                    if property(selected, kTISPropertyInputSourceID) == arguments[2] { exit(0) }
                }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            }
            fail("更新已完成，但无法恢复输入源，请从菜单栏手动选择「桃酥」")
        default: fail("未知命令")
        }
    }
}
