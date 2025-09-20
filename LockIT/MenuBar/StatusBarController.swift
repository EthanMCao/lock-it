import AppKit

final class StatusBarController {
    private var statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "lock.circle", accessibilityDescription: "LockIT")
        constructMenu()
    }

    private func constructMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open LockIT", action: #selector(openApp), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Lock All", action: #selector(lockAll), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func lockAll() {
        Task { await FolderListViewModel.shared.lockAll() }
    }

    @objc private func quit() {
        Task { @MainActor in
            await FolderListViewModel.shared.lockAll()
            await MainActor.run {
                NSApp.terminate(nil)
            }
        }
    }
}

