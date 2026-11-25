import Foundation

enum Shell {
    /// Runs a command through /bin/sh and returns (exit code, combined output).
    @discardableResult
    static func run(_ command: String) -> (code: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// Runs a shell script as root. macOS shows its standard admin password prompt once.
    /// Returns nil on success, or an error message.
    static func runAsAdmin(_ script: String) -> String? {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        guard let apple = NSAppleScript(source: source) else { return "Could not build AppleScript" }
        apple.executeAndReturnError(&error)
        if let error = error {
            return (error[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
        }
        return nil
    }

    /// True if something is listening on 127.0.0.1:port.
    static func isListening(port: Int) -> Bool {
        run("/usr/bin/nc -z -G 1 127.0.0.1 \(port)").code == 0
    }
}
