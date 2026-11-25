import SwiftUI
import AppKit

struct SetupView: View {
    @ObservedObject var state: SystemState
    var onFixAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(state.checks) { check in
                        CheckRow(check: check) { state.apply(check) }
                        Divider()
                    }
                }
                .padding(.trailing, 6)
            }
            Divider()
            connectionInfo
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 620)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(state.isServerReady ? "✅" : "☕️").font(.system(size: 38))
            VStack(alignment: .leading, spacing: 3) {
                Text(state.isServerReady ? "This Mac is ready to run 24/7" : "Set up this Mac as an always-on server")
                    .font(.title2).bold()
                Text(state.isServerReady
                     ? "It won't sleep, comes back after power cuts, and accepts SSH."
                     : "\(state.pendingRequired.count) required item(s) left. Fix All handles what it can with one password prompt, then walks you through the rest.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let msg = state.lastMessage {
                    Text(msg).font(.callout).foregroundColor(msg.hasPrefix("Error") ? .red : .green)
                }
            }
            Spacer()
            VStack(spacing: 6) {
                Button("Fix All", action: onFixAll)
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.isServerReady)
                Button("Refresh") { state.refresh() }
            }
        }
    }

    private var connectionInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect to this Mac").font(.headline)
            InfoLine(label: "SSH", value: "ssh \(state.userName)@\(state.hostName).local")
            if !state.localIP.isEmpty {
                InfoLine(label: "SSH (IP)", value: "ssh \(state.userName)@\(state.localIP)")
            }
            InfoLine(label: "Screen", value: "vnc://\(state.hostName).local")
        }
    }
}

struct CheckRow: View {
    let check: Check
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(check.status.symbol).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(check.title).font(.headline)
                    if !check.required {
                        Text("optional").font(.caption).foregroundColor(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.5)))
                    }
                }
                Text(check.current).font(.callout).foregroundColor(check.status == .ok ? .green : .orange)
                Text(check.why).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if check.status != .ok, let fix = check.fix {
                Button(buttonTitle(fix), action: action)
            }
        }
    }

    private func buttonTitle(_ fix: Fix) -> String {
        switch fix {
        case .admin, .local, .adminThenGuide: return "Turn On"
        case .guide: return "Show Me"
        }
    }
}

struct InfoLine: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
            Text(value).font(.system(.body, design: .monospaced))
            Spacer()
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
        }
    }
}
