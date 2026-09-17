import SwiftUI
import AppKit
import UserNotifications
import ReclaimCore

@MainActor
final class SettingsModel: ObservableObject {
    @Published var pollSeconds = 30
    @Published var autoKill = false
    @Published var startAtLogin = LoginItem.isEnabled
    @Published var loginNeedsApproval = LoginItem.needsApproval
    @Published var cliStatus = CLIInstall.status
    @Published var message: String?
    @Published var notify = true
    @Published var cpuPercent = 50
    @Published var cpuMinutes = 30
    @Published var memoryGB = 4
    @Published var memoryMinutes = 10
    @Published var swapPercent = 80
    @Published var thermal = true
    @Published var batteryDrain = 20
    @Published var notificationStatus = ""

    init(config: Config) {
        load(config: config)
    }

    func load(config: Config) {
        pollSeconds = config.pollSeconds
        autoKill = config.autoKill
        notify = config.alerts.notify
        cpuPercent = Int(config.alerts.cpu.percent)
        cpuMinutes = config.alerts.cpu.minutes
        memoryGB = Int(config.alerts.memory.gigabytes)
        memoryMinutes = config.alerts.memory.minutes
        swapPercent = Int(config.alerts.swapPercent)
        thermal = config.alerts.thermal
        batteryDrain = Int(config.alerts.batteryDrainPerHour)
    }

    func refreshNotificationStatus(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional: notificationStatus = ""
        case .denied: notificationStatus = "Notifications are off for Reclaim in System Settings."
        default: notificationStatus = "Notifications have not been allowed yet."
        }
    }

    /// Reads the file first: Config.save merges over what is there, and must not overwrite a broken file with defaults.
    func save() {
        switch Config.load() {
        case .failure(let error):
            message = "config.json is invalid, fix it before changing settings here: \(error)"
        case .success(var config):
            config.pollSeconds = min(3600, max(5, pollSeconds))
            config.autoKill = autoKill
            config.alerts.notify = notify
            config.alerts.cpu = CPUAlert(percent: Double(cpuPercent), minutes: cpuMinutes)
            config.alerts.memory = MemoryAlert(gigabytes: Double(memoryGB), minutes: memoryMinutes)
            config.alerts.swapPercent = Double(swapPercent)
            config.alerts.thermal = thermal
            config.alerts.batteryDrainPerHour = Double(batteryDrain)
            do { try config.save(); message = nil } catch { message = "could not write config.json: \(error)" }
        }
    }

    func applyLoginItem() {
        do {
            try LoginItem.set(startAtLogin)
            message = nil
        } catch {
            startAtLogin = LoginItem.isEnabled
            message = "could not change the login item: \(error.localizedDescription)"
        }
        loginNeedsApproval = LoginItem.needsApproval
    }

    func installCLI() {
        do { try CLIInstall.install(); message = nil } catch { message = "could not install the CLI: \(error.localizedDescription)" }
        cliStatus = CLIInstall.status
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            general.tabItem { Text("General") }
            alerts.tabItem { Text("Alerts") }
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    var general: some View {
        Form {
            Section("General") {
                Stepper(value: Binding(get: { model.pollSeconds }, set: { model.pollSeconds = $0; model.save() }), in: 5...3600, step: 5) {
                    HStack {
                        Text("Check every")
                        Text("\(model.pollSeconds)s").font(.system(.body, design: .monospaced))
                    }
                }
                Toggle("Kill automatically", isOn: Binding(get: { model.autoKill }, set: { model.autoKill = $0; model.save() }))
                Text("Rows marked KILL are terminated on the next check without asking. Off, they wait for the Kill button.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Start at login", isOn: Binding(get: { model.startAtLogin }, set: { model.startAtLogin = $0; model.applyLoginItem() }))
                if model.loginNeedsApproval {
                    HStack {
                        Text("Waiting for approval in System Settings.").font(.callout).foregroundStyle(.secondary)
                        Button("Open") { LoginItem.openSystemSettings() }
                    }
                }
            }
            Section("Command line") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("~/.local/bin/reclaim").font(.system(.body, design: .monospaced))
                        Text(model.cliStatus).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Install") { model.installCLI() }
                }
                Text("`reclaim --dry-run --json` and the rest of the CLI, run by this app's binary.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    var alerts: some View {
        Form {
            Section("Notifications") {
                Toggle("Notify me", isOn: Binding(get: { model.notify }, set: { model.notify = $0; model.save() }))
                Text("A notification for each new row Reclaim would kill (with a Kill button), each automatic kill, and each alert below.")
                    .font(.callout).foregroundStyle(.secondary)
                if !model.notificationStatus.isEmpty {
                    HStack {
                        Text(model.notificationStatus).font(.callout).foregroundStyle(.secondary)
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    }
                }
            }
            Section("Sustained") {
                stepper("CPU over", value: \.cpuPercent, in: 10...100, step: 5, unit: "%")
                stepper("for", value: \.cpuMinutes, in: 1...240, step: 1, unit: "m")
                stepper("Memory over", value: \.memoryGB, in: 1...64, step: 1, unit: "GB")
                stepper("for", value: \.memoryMinutes, in: 1...240, step: 1, unit: "m")
                stepper("Swap over", value: \.swapPercent, in: 10...100, step: 5, unit: "%")
                Toggle("Thermal pressure", isOn: Binding(get: { model.thermal }, set: { model.thermal = $0; model.save() }))
                stepper("Battery draining over", value: \.batteryDrain, in: 5...100, step: 5, unit: "%/h")
                Text("Each fires once when it has held that long, and again only after it cleared.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    func stepper(_ label: String, value: ReferenceWritableKeyPath<SettingsModel, Int>, in range: ClosedRange<Int>, step: Int, unit: String) -> some View {
        Stepper(value: Binding(get: { model[keyPath: value] }, set: { model[keyPath: value] = $0; model.save() }), in: range, step: step) {
            HStack {
                Text(label)
                Text("\(model[keyPath: value])\(unit)").font(.system(.body, design: .monospaced))
            }
        }
    }
}
