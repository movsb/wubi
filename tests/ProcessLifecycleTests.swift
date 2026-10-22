import Foundation

func runProcessLifecycleTests() throws {
    check(!ProcessLifecycle.isRunning(0) && !ProcessLifecycle.isRunning(-1), "invalid process IDs never count as running")
    check(ProcessLifecycle.isRunning(ProcessInfo.processInfo.processIdentifier), "current PID is detected as running")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["30"]
    try process.run()
    defer {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
    }
    check(ProcessLifecycle.isRunning(process.processIdentifier), "live child is detected by actual PID")
    check(!ProcessLifecycle.waitForExit([process.processIdentifier], timeout: 0.05), "waiting for live PID times out")
    process.terminate()
    process.waitUntilExit()
    check(!ProcessLifecycle.isRunning(process.processIdentifier), "terminated PID is detected without AppKit lifecycle cache")
    check(ProcessLifecycle.waitForExit([process.processIdentifier], timeout: 0.1), "terminated PID no longer blocks reload")
    check(ProcessLifecycle.waitForExit([], timeout: 0), "no running input method requires no wait")
    print("PASS: actual process lifecycle and reload wait regressions")
}
