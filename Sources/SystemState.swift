import Foundation
import AppKit

enum CheckStatus {
    case ok          // configured
    case needsFix    // can be fixed automatically
    case manual      // needs the user to do something in System Settings
    case optional    // not configured, but not required

    var symbol: String {
        switch self {
        case .ok: return "✅"
        case .needsFix: return "⚠️"
        case .manual: return "👉"
        case .optional: return "⚪️"
        }
    }
}

enum Fix {
    /// Shell commands run as root (batched into one password prompt by "Fix All").
    case admin([String])
    /// Something the app can do without a password.
    case local(() -> Void)
    /// Open a System Settings pane and show the user what to click.
    case guide(pane: SettingsPane, steps: String)
    /// Try an admin command first; if the check still fails, fall back to a guide.
    case adminThenGuide([String], pane: SettingsPane, steps: String)
}

struct Check: Identifiable {
    let id: String
    let title: String
    let why: String
    var status: CheckStatus
    var current: String
    var fix: Fix?
    var required: Bool = true
}

enum SettingsPane {
    case sharing, users, lockScreen, energy, url(String)

    func open() {
        let modern = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0))
        let urlString: String
        switch self {
        case .sharing:
            urlString = modern ? "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
                               : "x-apple.systempreferences:com.apple.preferences.sharing"
        case .users:
            urlString = modern ? "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"
                               : "x-apple.systempreferences:com.apple.preferences.users"
        case .lockScreen:
            urlString = modern ? "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension"
                               : "x-apple.systempreferences:com.apple.preference.security"
        case .energy:
            urlString = modern ? "x-apple.systempreferences:com.apple.Battery-Settings.extension"
                               : "x-apple.systempreferences:com.apple.preference.energysaver"
        case .url(let s):
            urlString = s
        }
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}

/// Reads the machine's current configuration and turns it into a list of checks.
final class SystemState: ObservableObject {
    @Published private(set) var checks: [Check] = []
    @Published private(set) var isLaptop = false
    @Published private(set) var hostName = ""
    @Published private(set) var localIP = ""
    @Published private(set) var userName = NSUserName()
    @Published var lastMessage: String?

    var pendingRequired: [Check] { checks.filter { $0.required && $0.status != .ok } }
    var isServerReady: Bool { pendingRequired.isEmpty }

    // MARK: Refresh

    func refresh() {
        let batt = Shell.run("/usr/bin/pmset -g batt").output
        isLaptop = batt.contains("InternalBattery")
        let pm = Self.parsePmset(Shell.run("/usr/bin/pmset -g custom").output, laptop: isLaptop)
        let live = Shell.run("/usr/bin/pmset -g").output
        let sleepDisabled = live.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil

        hostName = Shell.run("/usr/sbin/scutil --get LocalHostName").output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        localIP = Self.primaryIP()

        // Laptops: only change the "on charger" profile so battery life is left alone.
        let scope = isLaptop ? "-c" : "-a"
        var list: [Check] = []

        let sleep = pm["sleep"] ?? "?"
        list.append(Check(
            id: "sleep", title: "Never sleep automatically",
            why: "The Mac must never go to sleep on its own, or SSH and anything you run on it stops responding." +
                 (isLaptop ? " (Applied to the 'on power adapter' profile only.)" : ""),
            status: sleep == "0" ? .ok : .needsFix,
            current: sleep == "0" ? "System sleep: Never" : "System sleep after \(sleep) min",
            fix: .admin(["/usr/bin/pmset \(scope) sleep 0"])))

        let disk = pm["disksleep"] ?? "?"
        list.append(Check(
            id: "disksleep", title: "Never spin down disks",
            why: "Prevents external/internal disks from sleeping, which causes stalls for servers and backups.",
            status: disk == "0" ? .ok : .needsFix,
            current: disk == "0" ? "Disk sleep: Never" : "Disk sleep after \(disk) min",
            fix: .admin(["/usr/bin/pmset \(scope) disksleep 0"])))

        if let womp = pm["womp"] {
            list.append(Check(
                id: "womp", title: "Wake for network access",
                why: "Lets the Mac wake up when another device tries to connect to it (SSH, file sharing, Wake-on-LAN).",
                status: womp == "1" ? .ok : .needsFix,
                current: womp == "1" ? "On" : "Off",
                fix: .admin(["/usr/bin/pmset \(scope) womp 1"])))
        }

        if let ar = pm["autorestart"] {
            list.append(Check(
                id: "autorestart", title: "Start up after a power failure",
                why: "Turns the Mac back on automatically when power returns after an outage.",
                status: ar == "1" ? .ok : .needsFix,
                current: ar == "1" ? "On" : "Off",
                fix: .admin(["/usr/bin/pmset -a autorestart 1"])))
        }

        if let pn = pm["powernap"] {
            list.append(Check(
                id: "powernap", title: "Power Nap off",
                why: "Power Nap makes the Mac half-sleep/half-wake. On an always-on machine it just adds flaky wake cycles.",
                status: pn == "0" ? .ok : .needsFix,
                current: pn == "0" ? "Off" : "On",
                fix: .admin(["/usr/bin/pmset \(scope) powernap 0"]),
                required: false))
        }

        if isLaptop {
            list.append(Check(
                id: "lid", title: "Stay awake with the lid closed",
                why: "For laptops used as servers: keeps running when the lid is shut. Watch temperatures; leave the lid slightly open if it gets hot.",
                status: sleepDisabled ? .ok : .optional,
                current: sleepDisabled ? "On" : "Off (closing the lid will sleep the Mac)",
                fix: .admin(["/usr/bin/pmset -a disablesleep 1"]),
                required: false))
        }

        let ssh = Shell.isListening(port: 22)
        list.append(Check(
            id: "ssh", title: "Remote Login (SSH)",
            why: "Lets you control this Mac from another computer with: ssh \(userName)@\(hostName).local",
            status: ssh ? .ok : .needsFix,
            current: ssh ? "On (port 22 is listening)" : "Off",
            fix: .adminThenGuide(
                ["/usr/sbin/systemsetup -f -setremotelogin on 2>/dev/null || /bin/launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true"],
                pane: .sharing,
                steps: "In Sharing, turn on “Remote Login”. Click the ⓘ next to it and allow access for your user (or All users).")))

        let vnc = Shell.isListening(port: 5900)
        list.append(Check(
            id: "screensharing", title: "Screen Sharing",
            why: "Lets you see and control the desktop remotely (Finder → Go → Connect to Server → vnc://\(hostName).local). Needed for anything that only works in the GUI.",
            status: vnc ? .ok : .manual,
            current: vnc ? "On (port 5900 is listening)" : "Off",
            fix: .guide(pane: .sharing,
                        steps: "In Sharing, turn on “Screen Sharing” (and optionally “Remote Management”). macOS doesn't allow apps to switch this on for you."),
            required: false))

        let autoLoginUser = Shell.run("/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null")
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileVaultOn = Shell.run("/usr/bin/fdesetup isactive").output.contains("true")
        let autoLoginOK = !autoLoginUser.isEmpty
        let autoLoginWhy = "After a reboot or power cut, the Mac logs straight in so apps (and this one) start again without anyone at the keyboard."
        if autoLoginOK {
            list.append(Check(id: "autologin", title: "Automatic login after restart", why: autoLoginWhy,
                              status: .ok, current: "Logs in as \(autoLoginUser)", fix: nil))
        } else if fileVaultOn {
            list.append(Check(
                id: "autologin", title: "Automatic login after restart", why: autoLoginWhy,
                status: .manual, current: "Unavailable: FileVault is on",
                fix: .guide(pane: .url("x-apple.systempreferences:com.apple.preference.security?FDE"),
                            steps: "Automatic login needs FileVault off. Either turn FileVault off in Privacy & Security (less secure if the Mac is stolen), or keep it on and accept that after a power cut someone has to type the password once before SSH works."),
                required: false))
        } else {
            list.append(Check(
                id: "autologin", title: "Automatic login after restart", why: autoLoginWhy,
                status: .manual, current: "Off",
                fix: .guide(pane: .users,
                            steps: "In Users & Groups, set “Automatically log in as” to your user and enter your password. (Older macOS: click the lock first, then Login Options.)")))
        }

        list.append(Check(
            id: "loginitem", title: "Start Wakeful at login",
            why: "Keeps the stay-awake switch on and this checklist available after every restart.",
            status: LoginItem.isEnabled ? .ok : .needsFix,
            current: LoginItem.isEnabled ? "On" : "Off",
            fix: .local { LoginItem.setEnabled(true) }))

        let tailscale = FileManager.default.fileExists(atPath: "/Applications/Tailscale.app")
            || Shell.run("command -v tailscale").code == 0
        list.append(Check(
            id: "tailscale", title: "Reach it from anywhere (Tailscale)",
            why: "Optional. Without it you can only SSH in from the same Wi-Fi/LAN. Tailscale gives the Mac a private address you can reach from anywhere.",
            status: tailscale ? .ok : .optional,
            current: tailscale ? "Installed" : "Not installed",
            fix: .guide(pane: .url("https://tailscale.com/download/mac"),
                        steps: "Install Tailscale, sign in with the same account on this Mac and your laptop/phone, then SSH to its Tailscale name."),
            required: false))

        checks = list
    }

    // MARK: Fixing

    /// Applies one check's fix.
    func apply(_ check: Check) {
        guard let fix = check.fix else { return }
        switch fix {
        case .admin(let cmds):
            report(Shell.runAsAdmin(cmds.joined(separator: "; ")))
        case .local(let action):
            action()
        case .guide(let pane, let steps):
            showGuide(title: check.title, steps: steps, pane: pane)
        case .adminThenGuide(let cmds, let pane, let steps):
            let err = Shell.runAsAdmin(cmds.joined(separator: "; "))
            refresh()
            if err != nil || checks.first(where: { $0.id == check.id })?.status != .ok {
                showGuide(title: check.title, steps: steps, pane: pane)
            }
        }
        refresh()
    }

    /// One click: every automatic fix in a single password prompt, then guides for the rest.
    func fixAll() {
        refresh()
        var adminCmds: [String] = []
        var guided: [Check] = []
        for check in checks where check.status == .needsFix || (check.status == .manual && check.required) {
            switch check.fix {
            case .admin(let cmds): adminCmds += cmds
            case .adminThenGuide(let cmds, _, _): adminCmds += cmds; guided.append(check)
            case .local(let action): action()
            case .guide: guided.append(check)
            case .none: break
            }
        }
        if !adminCmds.isEmpty {
            // Restart automatically if the system freezes (not readable without root, so just set it).
            adminCmds.append("/usr/sbin/systemsetup -setrestartfreeze on >/dev/null 2>&1 || true")
            report(Shell.runAsAdmin(adminCmds.joined(separator: "; ")))
        }
        refresh()
        // Guide the user through what's still left, one at a time.
        guideLoop: for check in guided {
            guard let current = checks.first(where: { $0.id == check.id }), current.status != .ok else { continue }
            switch current.fix {
            case .guide(let pane, let steps), .adminThenGuide(_, let pane, let steps):
                if !showGuide(title: current.title, steps: steps, pane: pane, allowSkipAll: true) { break guideLoop }
            default: break
            }
            refresh()
        }
        refresh()
        lastMessage = isServerReady ? "All set. This Mac will stay awake and reachable." :
            "\(pendingRequired.count) item(s) still need attention."
    }

    /// Opens a settings pane and shows instructions. Returns false if the user chose to stop.
    @discardableResult
    private func showGuide(title: String, steps: String, pane: SettingsPane, allowSkipAll: Bool = false) -> Bool {
        pane.open()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = steps + "\n\nClick Done when you've finished."
        alert.addButton(withTitle: "Done")
        if allowSkipAll { alert.addButton(withTitle: "Stop for now") }
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func report(_ error: String?) {
        guard let error = error else { return }
        if error.contains("User canceled") || error.contains("-128") { return }
        lastMessage = "Error: \(error)"
    }

    // MARK: Parsing helpers

    /// Picks the AC Power section of `pmset -g custom` (desktops only have that one).
    static func parsePmset(_ text: String, laptop: Bool) -> [String: String] {
        var sections: [String: [String: String]] = [:]
        var current = "AC Power"
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            if line.hasSuffix(":") && !line.hasPrefix(" ") {
                current = String(line.dropLast()); continue
            }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            sections[current, default: [:]][String(parts[0])] = String(parts[1])
        }
        return sections["AC Power"] ?? sections.values.first ?? [:]
    }

    static func primaryIP() -> String {
        let iface = Shell.run("/sbin/route -n get default 2>/dev/null | awk '/interface:/{print $2}'")
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !iface.isEmpty else { return "" }
        return Shell.run("/usr/sbin/ipconfig getifaddr \(iface)").output
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
