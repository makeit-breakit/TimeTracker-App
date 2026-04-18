# TimeTracker

A lightweight macOS menu-bar app that tracks how much time you spend on each website, per day. Runs as a background agent (no dock icon), reads the active tab URL from your browser, and aggregates seconds per domain.

Supported browsers: **Safari** and **Brave**. Chrome support is a ~5-line addition (see [Adding a browser](#adding-a-browser)).

## How it works

- Polls the frontmost app every 5 seconds
- If it's a tracked browser, queries the active tab URL via AppleScript
- Extracts the domain (strips `www.`) and credits 5 seconds to that domain's running total
- Flushes the day's totals to disk every 30 seconds as JSON
- Resets the "today" window at 03:00 local time (so late-night browsing stays on the correct day)
- Stops crediting when the user has been idle >60 seconds (screensaver, lock, AFK)

Tracked data lives at `~/Library/Application Support/TimeTracker/YYYY-MM-DD.json` — one file per day, never uploaded anywhere.

## Requirements

- macOS 13 (Ventura) or later
- [Homebrew](https://brew.sh)
- Xcode (for the Swift toolchain and build)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — installed automatically by `setup.sh`

## Setup

```bash
./setup.sh
```

This will:
1. Install `xcodegen` via Homebrew if missing
2. Generate `TimeTracker.xcodeproj` from `project.yml`

Then open the project and build:

```bash
open TimeTracker.xcodeproj
# In Xcode: press Cmd+R
```

On first run, macOS will prompt you to allow TimeTracker to control Safari and/or Brave. Approve both — without this permission the app can't read the active tab URL and the menu will show an "Allow access" warning. You can revisit this at any time in **System Settings → Privacy & Security → Automation**.

## Usage

Click the status bar item (shows the current domain's total time, or `—` when idle) to see:
- Today's top 15 domains, sorted by time spent, active one in bold
- A reset button for the current day
- Quit

## Known limitations

- **Ad-hoc signed builds lose Automation permission on each rebuild.** The project uses `CODE_SIGN_IDENTITY: "-"` (`project.yml`), so macOS treats every rebuild as a different app and forgets your prior Automation grant. If the menu shows the "Allow access" warning after rebuilding, re-approve Safari/Brave under Privacy & Security → Automation. Switching to a real Developer ID would fix this.
- **First 30 seconds after launching a browser aren't tracked.** A grace period avoids a startup race where AppleScript can hang for 30s against a browser that isn't ready yet (see `BrowserTracker.swift:25`).
- **Only Safari and Brave** are tracked out of the box. See below.
- **Not sandboxed** — uses AppleScript automation, which is incompatible with the App Sandbox. Not App Store distributable without a rewrite.

## Adding a browser

Chrome's AppleScript dictionary is identical to Brave's. To add it:

1. In `TimeTracker/Tracking/BrowserTracker.swift`, add `"com.google.Chrome"` to `trackedBundleIDs`
2. Add a third `NSAppleScript` targeting `tell application "Google Chrome"`
3. Add a `case "com.google.Chrome": script = chromeScript` to the switch
4. In `TimeTracker/TimeTracker.entitlements`, add `<string>com.google.Chrome</string>` to the automation array
5. Rebuild

Firefox is harder — it doesn't expose a scriptable tab URL and would need a native-messaging bridge via a WebExtension.

## Project layout

```
TimeTracker/
├── project.yml                      # xcodegen spec (single source of truth)
├── setup.sh                         # xcodegen bootstrap
└── TimeTracker/
    ├── TimeTracker.entitlements     # Apple Events automation grants
    ├── App/
    │   ├── main.swift               # NSApplication entry point
    │   ├── AppDelegate.swift        # status bar, timers, lifecycle
    │   └── Info.plist               # LSUIElement=true (no dock icon)
    ├── Menu/
    │   └── MenuBuilder.swift        # status-bar dropdown content
    ├── Model/
    │   ├── Store.swift              # JSON persistence, day rollover
    │   └── TimeRecord.swift         # Codable data structures
    └── Tracking/
        └── BrowserTracker.swift     # AppleScript polling, idle detection
```
