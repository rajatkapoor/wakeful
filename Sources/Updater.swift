import AppKit
import Sparkle

/// Sparkle auto-update. The feed (SUFeedURL in Info.plist) is appcast.xml on the latest release of
/// this repo (rajatkapoor/wakeful). Every update zip is EdDSA-signed (SUPublicEDKey),
/// so Sparkle refuses anything not signed with our key. Checks run once a day.
final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!
    /// Set when a check finds a newer version; shown in the menu.
    private(set) var availableVersion: String?
    var onChange: (() -> Void)?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        onChange?()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableVersion = nil
        onChange?()
    }

    // MARK: SPUStandardUserDriverDelegate

    // Wakeful is a menu bar app with no Dock icon: let Sparkle bring its update window forward
    // for scheduled checks, and keep the menu item as a reminder until the user installs.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}
