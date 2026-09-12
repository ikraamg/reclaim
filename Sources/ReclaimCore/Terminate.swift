import Foundation

public enum Terminate {
    /// SIGTERM, wait `grace`, SIGKILL if it is still there.
    public static func run(pid: Int32, grace: TimeInterval = 2) -> String {
        guard pid > 1 else { return "refused: pid \(pid) is not a single user process" }
        if kill(pid, SIGTERM) != 0 {
            return errno == ESRCH ? "already gone" : String(cString: strerror(errno))
        }
        Thread.sleep(forTimeInterval: grace)
        if kill(pid, 0) != 0 { return "terminated" }
        return kill(pid, SIGKILL) == 0 ? "killed (-9, ignored TERM)" : "terminated"
    }
}
