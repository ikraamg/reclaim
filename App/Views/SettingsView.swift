import SwiftUI
import ReclaimCore

@MainActor
final class SettingsModel: ObservableObject {
    @Published var pollSeconds: Int
    @Published var autoKill: Bool
    @Published var startAtLogin = LoginItem.isEnabled
    @Published var loginNeedsApproval = LoginItem.needsApproval
    @Published var message: String?

    init(config: Config) {
        pollSeconds = config.pollSeconds
        autoKill = config.autoKill
    }

    /// Reads the file first: Config.save merges over what is there, and must not overwrite a broken file with defaults.
    func save() {
        switch Config.load() {
        case .failure(let error):
            message = "config.json is invalid, fix it before changing settings here: \(error)"
        case .success(var config):
            config.pollSeconds = min(3600, max(5, pollSeconds))
            config.autoKill = autoKill
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
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
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
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
