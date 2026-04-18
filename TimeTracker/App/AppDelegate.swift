import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var store: Store!
    private var tracker: BrowserTracker!
    private var flushTimer: Timer?
    private var titleTimer: Timer?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSApp.terminate(nil)
            return
        }

        store = Store()
        store.load()

        tracker = BrowserTracker(store: store)
        tracker.onDomainChanged = { [weak self] in self?.updateTitle() }
        tracker.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        statusItem.button?.title = "—"
        statusItem.button?.setAccessibilityLabel("TimeTracker")

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Flush data to disk every 30 seconds
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.store.flush()
        }

        // Refresh the status bar title every minute (also refreshes on menuWillOpen)
        titleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateTitle()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        store?.flush()
    }

    // MARK: - Title

    func updateTitle() {
        guard let domain = tracker.activeDomain else {
            statusItem.button?.title = "—"
            return
        }
        // Use stored seconds if available; 0 if the domain was just created (e.g. right after reset).
        let seconds = store.record.domains[domain]?.totalSeconds ?? 0
        statusItem.button?.title = MenuBuilder.formatSeconds(seconds)
    }

    // MARK: - Reset

    @objc private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset today's data?"
        alert.informativeText = "All tracked time for today will be cleared."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.resetToday()
        updateTitle()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateTitle()
        MenuBuilder.rebuild(menu: menu, store: store, tracker: tracker,
                            resetTarget: self, resetAction: #selector(confirmReset))
    }
}
