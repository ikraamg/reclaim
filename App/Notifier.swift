import UserNotifications
import os
import ReclaimCore

/// Posts Monitor events as notifications and routes the Kill action back to the model.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let killCategory = "kill"
    nonisolated static let killAction = "kill"

    private let center = UNUserNotificationCenter.current()
    private let log = Logger(subsystem: "com.ikraam.Reclaim", category: "alerts")
    var onKill: (Int32, String) -> Void = { _, _ in }

    func start() {
        center.delegate = self
        let kill = UNNotificationAction(identifier: Self.killAction, title: "Kill", options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.killCategory, actions: [kill], intentIdentifiers: [], options: [])])
    }

    func requestAuthorizationIfUndecided() async {
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            log.notice("notifications \(granted ? "allowed" : "denied", privacy: .public)")
        } catch {
            log.error("notification authorization failed: \(String(describing: error), privacy: .public)")
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }

    func post(_ event: Monitor.Event) {
        let content = UNMutableNotificationContent()
        let identifier: String
        switch event {
        case .killCandidate(let f):
            content.title = "Would kill \(f.process.name)"
            content.body = f.reason
            content.categoryIdentifier = Self.killCategory
            content.userInfo = ["pid": Int(f.process.pid), "command": f.process.command]
            identifier = "kill-\(f.process.pid)"
        case .killed(let f, let action):
            content.title = "Killed \(f.process.name)"
            content.body = "\(action) · \(f.reason)"
            identifier = "killed-\(f.process.pid)"
            center.removeDeliveredNotifications(withIdentifiers: ["kill-\(f.process.pid)"])
        case .sustained(let alert):
            content.title = alert.title
            content.body = alert.detail
            identifier = "\(alert.kind.rawValue)-\(alert.pid.map(String.init) ?? "machine")"
        }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        Task {
            do { try await center.add(request); log.notice("posted \(identifier, privacy: .public)") }
            catch { log.error("could not post \(identifier, privacy: .public): \(String(describing: error), privacy: .public)") }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == Self.killAction else { return }
        let info = response.notification.request.content.userInfo
        guard let pid = info["pid"] as? Int, let command = info["command"] as? String else { return }
        await MainActor.run { onKill(Int32(pid), command) }
    }
}
