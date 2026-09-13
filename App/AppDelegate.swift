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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config: Config
        var configError: String?
        switch Config.load() {
        case .success(let c): config = c
        case .failure(let e): config = Config(); configError = String(describing: e)
        }
        model = AppModel(config: config)
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
        model.$monitor.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.showCount($0.killCount) }
            .store(in: &subscriptions)
        showCount(0)
        model.start()
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
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Reclaim", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        statusItem.menu = menu
        defer { statusItem.menu = nil }
        statusItem.button?.performClick(nil)
    }

    @objc func openSettings() {
        // Task 10
    }
}

struct LivePopoverView: View {
    @ObservedObject var model: AppModel
    let actions: PopoverActions
    var body: some View { PopoverView(monitor: model.monitor, actions: actions) }
}
