import Foundation
import Combine
import os
import ReclaimCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var monitor: Monitor
    private let machine: Machine
    private let log = Logger(subsystem: "com.ikraam.Reclaim", category: "monitor")
    private var loop: Task<Void, Never>?
    private var ticking = false
    var notify: (Monitor.Event) -> Void = { _ in }

    init(config: Config, machine: Machine = .live) {
        monitor = Monitor(config: config)
        self.machine = machine
    }

    func start() { restartLoop() }

    private func restartLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await tick()
                let seconds = max(5, monitor.config.pollSeconds)
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func tick() async {
        if ticking { return }
        ticking = true
        defer { ticking = false }
        let config = monitor.config, previous = monitor.runState, machine = machine
        let result = await Task.detached {
            Pipeline.run(config: config, dryRun: !config.autoKill, previous: previous, on: machine)
        }.value
        switch result {
        case .success(let report):
            let events = monitor.apply(report, at: Date())
            for event in events { log.notice("event: \(String(describing: event).prefix(120), privacy: .public)") }
            if monitor.config.alerts.notify { events.forEach(notify) }
            for (pid, action) in report.actions { log.notice("killed \(pid): \(action, privacy: .public)") }
        case .failure(let error):
            monitor.apply(failure: error, at: Date())
            log.error("pass failed: \(String(describing: error), privacy: .public)")
        }
    }

    func kill(_ pid: Int32) { kill([pid]) }

    /// A notification's Kill: the row must still be the process the notification named.
    func kill(_ pid: Int32, expecting command: String) {
        guard monitor.killRows.contains(where: { $0.process.pid == pid && $0.process.command == command }),
              monitor.action(for: pid) == nil else {
            log.notice("stale notification for \(pid), not killing")
            return
        }
        kill(pid)
    }

    func killAll() {
        kill(monitor.killRows.map(\.process.pid).filter { monitor.action(for: $0) == nil })
    }

    /// Terminate runs off the main thread (it waits two seconds for SIGTERM), then a fresh pass shows what is left.
    private func kill(_ pids: [Int32]) {
        let records = pids.compactMap { pid in monitor.findings.first { $0.process.pid == pid && Monitor.canKill($0) }?.process }
        for record in records { monitor.beginKill(record.pid) }
        let machine = machine
        Task {
            for record in records {
                let result = await Task.detached { machine.terminate(record) }.value
                monitor.finishKill(record.pid, result: result)
                log.notice("kill \(record.pid) by button: \(result, privacy: .public)")
            }
            await tick()
        }
    }

    func apply(config: Config) {
        let intervalChanged = config.pollSeconds != monitor.config.pollSeconds
        monitor.apply(config: config)
        log.notice("config applied: every \(config.pollSeconds)s, autoKill \(config.autoKill)")
        if intervalChanged { restartLoop() }
    }

    func reject(configMessage: String) {
        monitor.reject(configMessage: configMessage, at: Date())
        log.error("config rejected: \(configMessage, privacy: .public)")
    }
}
