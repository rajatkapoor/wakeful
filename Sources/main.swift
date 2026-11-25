import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let state = SystemState()
    private let keepAwake = KeepAwake()
    private let updater = Updater()
    private var window: NSWindow?
    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["keepAwake": true])
        keepAwake.set(defaults.bool(forKey: "keepAwake"))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        updater.onChange = { [weak self] in self?.updateIcon() }
        if CommandLine.arguments.contains("--check-updates") { updater.checkForUpdates() }

        state.refresh()
        updateIcon()

        // First run, or something's missing: open the guided setup.
        if !defaults.bool(forKey: "hasLaunched") || !state.isServerReady {
            defaults.set(true, forKey: "hasLaunched")
            openSetup()
        }

        // Re-check periodically so the icon reflects reality (e.g. someone changed a setting).
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.state.refresh(); self?.updateIcon()
        }
    }

    private func updateIcon() {
        let name = state.isServerReady ? "cup.and.saucer.fill" : "cup.and.saucer"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Wakeful")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = state.isServerReady ? "Wakeful: server ready" : "Wakeful: setup incomplete"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        state.refresh()
        updateIcon()
        menu.removeAllItems()

        let headline = state.isServerReady
            ? "Server ready: stays awake & reachable"
            : "\(state.pendingRequired.count) item(s) need attention"
        menu.addItem(disabled(headline))
        menu.addItem(.separator())

        let awake = item("Keep Awake Now", #selector(toggleKeepAwake))
        awake.state = keepAwake.isActive ? .on : .off
        menu.addItem(awake)
        menu.addItem(.separator())

        menu.addItem(disabled("\(state.hostName).local\(state.localIP.isEmpty ? "" : "  ·  \(state.localIP)")"))
        menu.addItem(item("Copy SSH Command", #selector(copySSH)))
        menu.addItem(.separator())

        for check in state.checks {
            let suffix = check.required ? "" : "  (optional)"
            let mi = item("\(check.status.symbol)  \(check.title)\(suffix)", #selector(applyCheck(_:)))
            mi.representedObject = check.id
            mi.toolTip = "\(check.current)\n\n\(check.why)"
            if check.status == .ok { mi.action = nil }
            menu.addItem(mi)
        }
        menu.addItem(.separator())

        let fixAll = item("Fix All (One Click)…", #selector(fixAll))
        if state.isServerReady { fixAll.action = nil }
        menu.addItem(fixAll)
        menu.addItem(item("Open Setup Guide…", #selector(openSetup)))
        menu.addItem(.separator())
        if let version = updater.availableVersion {
            menu.addItem(item("⬆️  Update Available: Version \(version)…", #selector(checkForUpdates)))
        } else {
            menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        }
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        menu.addItem(disabled("Wakeful \(current)"))
        menu.addItem(item("Quit Wakeful", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        return mi
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        return mi
    }

    // MARK: Actions

    @objc private func toggleKeepAwake() {
        keepAwake.set(!keepAwake.isActive)
        defaults.set(keepAwake.isActive, forKey: "keepAwake")
    }

    @objc private func copySSH() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("ssh \(state.userName)@\(state.hostName).local", forType: .string)
    }

    @objc private func applyCheck(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let check = state.checks.first(where: { $0.id == id }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        state.apply(check)
        updateIcon()
    }

    @objc private func fixAll() {
        NSApp.activate(ignoringOtherApps: true)
        state.fixAll()
        updateIcon()
        openSetup()
    }

    @objc private func openSetup() {
        state.refresh()
        if window == nil {
            let view = SetupView(state: state) { [weak self] in
                self?.state.fixAll(); self?.updateIcon()
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Wakeful Setup"
            w.contentViewController = NSHostingController(rootView: view)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func checkForUpdates() { updater.checkForUpdates() }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
