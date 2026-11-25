import Foundation
import IOKit.pwr_mgt

/// Holds a power assertion that blocks idle sleep while the app runs. No password needed.
/// This is the instant "keep awake" switch; the pmset settings make it permanent system-wide.
final class KeepAwake {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    func set(_ on: Bool) {
        if on == isActive { return }
        if on {
            let reason = "Wakeful: keeping this Mac awake" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertionID)
            isActive = (result == kIOReturnSuccess)
        } else {
            IOPMAssertionRelease(assertionID)
            isActive = false
        }
    }
}

/// Launch-at-login via a LaunchAgent in ~/Library/LaunchAgents. Works on every macOS version.
enum LoginItem {
    static let label = "dev.wakeful.app"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func setEnabled(_ on: Bool) {
        if on {
            let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [exe],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
            ]
            try? FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: plistURL)
            }
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}
