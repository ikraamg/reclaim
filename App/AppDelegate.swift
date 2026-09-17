import AppKit
import SwiftUI
import Combine
import ReclaimCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var model: AppModel!
    private var subscriptions: Set<AnyCancellable> = []
    private var configWatcher: ConfigWatcher?
    private var settingsWindow: NSWindow?
    private lazy var settingsModel = SettingsModel(config: model.monitor.config)
    private let notifier = Notifier()

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifier.start()
        NSApp.mainMenu = mainMenu()
        let config: Config
        var configError: String?
        switch Config.load() {
        case .success(let c): config = c
        case .failure(let e): config = Config(); configError = String(describing: e)
        }
        model = AppModel(config: config)
        model.notify = { [weak self] in self?.notifier.post($0) }
        notifier.onKill = { [weak self] pid, command in self?.model.kill(pid, expecting: command) }
        if let configError { model.reject(configMessage: configError) } else { model.apply(config: config) }

        let actions = PopoverActions(kill: { [weak self] in self?.model.kill($0) },
                                     killAll: { [weak self] in self?.model.killAll() },
                                     settings: { [weak self] in self?.openSettings() },
                                     quit: { NSApp.terminate(nil) })
        let hosting = NSHostingController(rootView: LivePopoverView(model: model, actions: actions))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        model.$monitor.sink { [weak self] in self?.showCount($0.killCount) }
            .store(in: &subscriptions)
        showCount(0)
        configWatcher = ConfigWatcher(fileURL: Config.defaultURL) { [weak self] in self?.reloadConfig() }
        configWatcher?.start()
        model.start()
        if config.alerts.notify { Task { await notifier.requestAuthorizationIfUndecided() } }
    }

    private func reloadConfig() {
        switch Config.load() {
        case .success(let config): model.apply(config: config)
        case .failure(let error): model.reject(configMessage: String(describing: error))
        }
    }

    private func showCount(_ count: Int) {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: count > 0 ? "square.fill" : "square", accessibilityDescription: "Reclaim")
        button.title = count > 0 ? String(count) : ""
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let secondary = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)
        if secondary { showMenu() } else { togglePopover(sender) }
    }

    private func togglePopover(_ button: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil); return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Reclaim", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        defer { statusItem.menu = nil }
        statusItem.button?.performClick(nil)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: settingsModel)))
            window.title = "Reclaim Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsModel.pollSeconds = model.monitor.config.pollSeconds
        settingsModel.autoKill = model.monitor.config.autoKill
        settingsModel.startAtLogin = LoginItem.isEnabled
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func mainMenu() -> NSMenu {
        let menu = NSMenu()
        let app = NSMenuItem()
        app.submenu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        app.submenu?.addItem(settings)
        app.submenu?.addItem(.separator())
        app.submenu?.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        app.submenu?.addItem(NSMenuItem(title: "Quit Reclaim", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.addItem(app)
        return menu
    }
}

struct LivePopoverView: View {
    @ObservedObject var model: AppModel
    let actions: PopoverActions
    var body: some View { PopoverView(monitor: model.monitor, actions: actions) }
}
