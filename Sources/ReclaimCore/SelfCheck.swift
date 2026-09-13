import Foundation

/// The KILL predicate must never fire on a live process. Shared by the tests and `reclaim --self-check`.
public enum SelfCheck {
    public struct Shape {
        public let name: String
        public let expectKill: Bool
        public let run: () -> Verdict?
    }

    static let tenDays = 10 * 86400

    static func record(pid: Int32 = 500, ppid: Int32 = 1, age: Int = tenDays,
                       user: String = "me", cpu: Double = 1.0, command: String) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: ppid, cpu: cpu, rssKB: 300_000, age: age, user: user, command: command)
    }

    /// pid 900 is a live parent; port 3000 is held by pid 77.
    static func context(_ processes: [ProcessRecord], listeners: [Int: Set<Int32>]? = [3000: [77]]) -> Context {
        let parent = record(pid: 900, command: "editor")
        return Context(processes: processes + [parent], me: "me", untouchable: [1],
                       listeners: listeners, cwds: [:], worktreeNote: { _ in "" })
    }

    static func verdict(_ p: ProcessRecord, extra: [ProcessRecord] = [],
                        listeners: [Int: Set<Int32>]? = [3000: [77]]) -> Verdict? {
        Classifier(config: Config()).classify(p, in: context([p] + extra, listeners: listeners))?.verdict
    }

    static func live(_ name: String, _ p: ProcessRecord, extra: [ProcessRecord] = [],
                     listeners: [Int: Set<Int32>]? = [3000: [77]]) -> Shape {
        Shape(name: name, expectKill: false) { verdict(p, extra: extra, listeners: listeners) }
    }

    static func dead(_ name: String, _ p: ProcessRecord) -> Shape {
        Shape(name: name, expectKill: true) { verdict(p) }
    }

    public static let shapes: [Shape] = [
        live("bound puma", record(pid: 77, command: "puma 8.0.2 (tcp://localhost:3000) [core]")),
        live("puma whose worker holds the port", record(pid: 76, command: "puma 8.0.2 (tcp://localhost:3000) [core]"),
             extra: [record(pid: 77, ppid: 76, command: "puma: cluster worker 0")]),
        live("puma still booting", record(age: 60, command: "puma 8.0.2 (tcp://localhost:9999) [new]")),
        live("young benchmark spin loop", record(age: 30, command: "zsh -c while :; do :; done")),
        live("parented spin loop", record(ppid: 4242, command: "zsh -c while :; do :; done")),
        live("watcher with a live parent", record(ppid: 900, command: "/gems/rb-fsevent-0.11.2/bin/fsevent_watch --format=otnetstring /repo")),
        live("MCP server whose editor is alive", record(ppid: 900, command: "npm exec chrome-devtools-mcp@1.2.0")),
        live("another user's process", record(user: "root", command: "zsh -c while :; do :; done")),
        live("puma when the lsof probe failed", record(command: "puma 8.0.2 (tcp://localhost:3111) [gone]"), listeners: nil),
        live("launchd itself", record(pid: 1, ppid: 0, command: "/sbin/launchd")),
        live("our own ancestor", record(pid: 1, command: "zsh -c while :; do :; done")),

        dead("orphaned spin loop", record(cpu: 99, command: "zsh -c 'while :; do :; done'")),
        dead("puma on an unbound port", record(command: "puma 8.0.2 (tcp://localhost:3111) [gone]")),
        dead("duplicate puma on a taken port", record(command: "puma 8.0.2 (tcp://localhost:3000) [dup]")),
        dead("orphaned watcher", record(command: "/gems/rb-fsevent-0.11.2/bin/fsevent_watch /repo")),
        dead("MCP server with a dead editor", record(ppid: 1, command: "npm exec chrome-devtools-mcp@1.2.0")),
    ]

    /// Empty when the predicate is safe and complete.
    public static func failures() -> [String] {
        shapes.compactMap { shape in
            let got = shape.run()
            if shape.expectKill && got != .kill { return "PREDICATE BLIND: missed dead process (\(shape.name))" }
            if !shape.expectKill && got == .kill { return "PREDICATE UNSAFE: would kill a live process (\(shape.name))" }
            return nil
        }
    }
}
