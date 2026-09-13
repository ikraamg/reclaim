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
            monitor.apply(report, at: Date())
            for (pid, action) in report.actions { log.notice("killed \(pid): \(action, privacy: .public)") }
        case .failure(let error):
            monitor.apply(failure: error, at: Date())
            log.error("pass failed: \(String(describing: error), privacy: .public)")
        }
    }

    func kill(_ pid: Int32) { kill([pid]) }

    func killAll() {
        kill(monitor.killRows.map(\.process.pid).filter { monitor.action(for: $0) == nil })
    }

    /// Terminate runs off the main thread (it waits two seconds for SIGTERM), then a fresh pass shows what is left.
    private func kill(_ pids: [Int32]) {
        for pid in pids { monitor.beginKill(pid) }
        let machine = machine
        Task {
            for pid in pids {
                let result = await Task.detached { machine.terminate(pid) }.value
                monitor.finishKill(pid, result: result)
                log.notice("kill \(pid) by button: \(result, privacy: .public)")
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
