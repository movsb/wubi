import Foundation
import Darwin

enum ProcessLifecycle {
    static func isRunning(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    static func waitForExit(_ pids: [pid_t], timeout: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while pids.contains(where: isRunning) {
            if Date() >= deadline { return false }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        return true
    }
}
