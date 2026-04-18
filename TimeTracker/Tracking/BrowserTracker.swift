import AppKit
import CoreGraphics
import OSLog

private let logger = Logger(subsystem: "com.timetracker.app", category: "BrowserTracker")

final class BrowserTracker {
    private(set) var activeDomain: String?
    private(set) var permissionDenied = false

    // Called immediately whenever activeDomain changes — lets AppDelegate refresh the title
    // without waiting for the 60-second timer.
    var onDomainChanged: (() -> Void)?

    private let store: Store
    private var pollTimer: Timer?

    // Browsers we track, keyed by bundle ID.
    private let trackedBundleIDs: Set<String> = ["com.apple.Safari", "com.brave.Browser"]

    // Tracks when each browser was last launched. Entry is removed on termination, so
    // launchTimes[id] != nil also serves as an O(1) "is running" check — replacing the
    // expensive NSWorkspace.runningApplications scan that used to happen every 5 seconds.
    private var launchTimes: [String: Date] = [:]
    private let launchGracePeriod: TimeInterval = 30

    // Pre-compiled AppleScript instances — allocated once, reused on every poll tick.
    // NSAppleScript must always be called on the main thread.
    private let safariScript: NSAppleScript? = NSAppleScript(source: """
        tell application "Safari"
            if (count of windows) > 0 then
                return URL of current tab of front window
            end if
        end tell
        """)

    private let braveScript: NSAppleScript? = NSAppleScript(source: """
        tell application "Brave Browser"
            if (count of windows) > 0 then
                return URL of active tab of front window
            end if
        end tell
        """)

    init(store: Store) {
        self.store = store
    }

    func start() {
        // Browsers already running before our app launched have had time to finish
        // starting up — mark them with a past timestamp so they're queryable immediately.
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, trackedBundleIDs.contains(id) {
                launchTimes[id] = Date(timeIntervalSinceNow: -(launchGracePeriod + 1))
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        // Timer fires on the main run loop — NSAppleScript main-thread requirement satisfied.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        setActiveDomain(nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Launch tracking

    @objc private func appLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let id = app.bundleIdentifier,
              trackedBundleIDs.contains(id) else { return }
        launchTimes[id] = Date()
    }

    @objc private func appTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let id = app.bundleIdentifier else { return }
        launchTimes.removeValue(forKey: id)
    }

    // MARK: - Polling

    private func poll() {
        // Stop crediting time when the user has been idle for more than 60 seconds.
        // This covers screensaver activation and screen lock, not just system sleep
        // (sleep already suspends the timer naturally).
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
        if idleSeconds > 60 {
            setActiveDomain(nil)
            return
        }

        guard let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            setActiveDomain(nil)
            return
        }

        let script: NSAppleScript?
        switch frontBundleID {
        case "com.apple.Safari":  script = safariScript
        case "com.brave.Browser": script = braveScript
        default:
            setActiveDomain(nil)
            return
        }

        // Guard: launchTimes entry exists iff the browser is running (removed on termination).
        // Prevents the 30-second AppleScript timeout that occurs when querying a quit browser.
        guard launchTimes[frontBundleID] != nil else {
            setActiveDomain(nil)
            return
        }

        // Guard: respect the post-launch grace period to avoid triggering startup race conditions.
        if let launchTime = launchTimes[frontBundleID],
           Date().timeIntervalSince(launchTime) < launchGracePeriod {
            setActiveDomain(nil)
            return
        }

        guard let appleScript = script else {
            setActiveDomain(nil)
            return
        }

        var errorDict: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorDict)
        if let error = errorDict {
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 {
                logger.warning("AppleScript automation permission denied for \(frontBundleID)")
                if !permissionDenied {
                    permissionDenied = true
                    onDomainChanged?()
                }
            }
            setActiveDomain(nil)
            return
        }

        if permissionDenied {
            permissionDenied = false
        }
        guard let urlString = result.stringValue,
              let domain = extractDomain(urlString) else {
            setActiveDomain(nil)
            return
        }

        setActiveDomain(domain)
        store.credit(domain: domain, seconds: 5)
    }

    // Only fires onDomainChanged when the value actually changes — prevents redundant title refreshes.
    private func setActiveDomain(_ newDomain: String?) {
        guard newDomain != activeDomain else { return }
        activeDomain = newDomain
        onDomainChanged?()
    }

    private func extractDomain(_ urlString: String) -> String? {
        guard let host = URL(string: urlString)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
