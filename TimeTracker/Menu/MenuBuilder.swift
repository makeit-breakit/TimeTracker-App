import AppKit

enum MenuBuilder {

    static func rebuild(menu: NSMenu, store: Store, tracker: BrowserTracker,
                        resetTarget: AnyObject, resetAction: Selector) {
        menu.removeAllItems()

        let header = NSMenuItem(title: todayHeader(), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        var items = store.record.domains
            .sorted { $0.value.totalSeconds > $1.value.totalSeconds }
            .prefix(15)
            .map { $0 }

        // Always include the active domain, even if it ranked outside the top 15.
        if let active = tracker.activeDomain, !items.contains(where: { $0.key == active }) {
            let session = store.record.domains[active] ?? DomainSession(totalSeconds: 0)
            items.append((key: active, value: session))
        }

        if tracker.permissionDenied {
            let warn = NSMenuItem(title: "Allow access: System Settings → Privacy & Security → Automation",
                                  action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }

        if items.isEmpty {
            let empty = NSMenuItem(title: "No data yet today", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (domain, session) in items {
                let timeStr = formatSeconds(session.totalSeconds)
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                item.isEnabled = false
                if domain == tracker.activeDomain {
                    item.attributedTitle = styledItem(domain: domain, time: timeStr, bold: true)
                } else {
                    item.attributedTitle = styledItem(domain: domain, time: timeStr, bold: false)
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let reset = NSMenuItem(title: "Reset Today's Data", action: resetAction, keyEquivalent: "")
        reset.target = resetTarget
        menu.addItem(reset)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit TimeTracker",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    static func formatSeconds(_ s: Int) -> String {
        if s < 60 { return "<1m" }
        if s < 3600 { return "\(s / 60)m" }
        let h = s / 3600
        let m = (s % 3600) / 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: - Private

    private static func todayHeader() -> String {
        let adjusted = Date().addingTimeInterval(-3 * 3600)
        return "Today — \(headerFormatter.string(from: adjusted))"
    }

    private static let headerFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMMM d"
        return fmt
    }()

    private static func styledItem(domain: String, time: String, bold: Bool) -> NSAttributedString {
        let font: NSFont = bold
            ? .boldSystemFont(ofSize: NSFont.systemFontSize)
            : .systemFont(ofSize: NSFont.systemFontSize)

        // Fixed-width columns: domain left-aligned, time right-aligned via tab stop
        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .right, location: 260)]
        para.defaultTabInterval = 260

        return NSAttributedString(
            string: "\(domain)\t\(time)",
            attributes: [.font: font, .paragraphStyle: para]
        )
    }
}
