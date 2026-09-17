import Foundation

public enum Terminate {
    /// Re-reads what the pid runs now; a pid recycled since the snapshot must not be signaled.
    public static func run(_ record: ProcessRecord, grace: TimeInterval = 2, currentCommand: (Int32) -> String?) -> String {
        guard let now = currentCommand(record.pid), !now.isEmpty else { return "already gone" }
        guard now == record.command else { return "gone: pid \(record.pid) now runs something else" }
        return run(pid: record.pid, grace: grace)
    }

    public static func currentCommand(_ pid: Int32) -> String? {
        shell(["/bin/ps", "-o", "command=", "-p", String(pid)])?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
