import Foundation

/// Everything the process pass reads from, or does to, the machine. `live` is the real one; tests build their own.
public struct Machine: Sendable {
    public var processes: @Sendable () -> [ProcessRecord]
    public var user: @Sendable () -> String?
    public var listeners: @Sendable () -> [Int: Set<Int32>]?
    public var cwd: @Sendable (Int32) -> String?
    public var worktreeNote: @Sendable (String?) -> String
    public var system: @Sendable () -> SystemState
    public var terminate: @Sendable (ProcessRecord) -> String
    public var selfPid: Int32
    public var parentPid: Int32
    public var isRoot: Bool

    public init(processes: @escaping @Sendable () -> [ProcessRecord],
                user: @escaping @Sendable () -> String?,
                listeners: @escaping @Sendable () -> [Int: Set<Int32>]?,
                cwd: @escaping @Sendable (Int32) -> String?,
                worktreeNote: @escaping @Sendable (String?) -> String,
                system: @escaping @Sendable () -> SystemState,
                terminate: @escaping @Sendable (ProcessRecord) -> String,
                selfPid: Int32, parentPid: Int32, isRoot: Bool) {
        self.processes = processes; self.user = user; self.listeners = listeners; self.cwd = cwd
        self.worktreeNote = worktreeNote; self.system = system; self.terminate = terminate
        self.selfPid = selfPid; self.parentPid = parentPid; self.isRoot = isRoot
    }

    public static let live = Machine(
        processes: { ProcessSnapshot.live() },
        user: { shell(["/usr/bin/id", "-un"])?.trimmingCharacters(in: .whitespacesAndNewlines) },
        listeners: { Probe.listeners() },
        cwd: { Probe.cwd(of: $0) },
        worktreeNote: { Worktree.note(cwd: $0) },
        system: { SystemState.read() },
        terminate: { Terminate.run($0, currentCommand: Terminate.currentCommand) },
        selfPid: getpid(), parentPid: getppid(), isRoot: getuid() == 0)
}
