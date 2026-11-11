import ArgumentParser
import Foundation
import USBBlockCore

/// Reports the daemon version and the state of each configured rule.
struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show daemon and configured device state.")

    /// Combines config, registry and live state to show blocked or waiting devices.
    func run() throws {
        let config = try readConfig()
        let state = runningState()
        print("usbblock \(usbblockVersion)")
        if let state {
            let date = state.started.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
            print("Daemon:  running (pid \(state.pid), started \(date))")
        } else if LaunchDaemon.isInstalled {
            print("Daemon:  enabled but not running; check `usbblock logs`.")
        } else {
            print("Daemon:  disabled")
        }
        print("Config:  \(Config.path)")
        if let state, state.version != usbblockVersion {
            print("The daemon is running \(state.version) and this CLI is \(usbblockVersion). Run `sudo usbblock enable` to update it.")
        }
        print()
        guard !config.entries.isEmpty else {
            print("No devices configured yet. Add some with: sudo usbblock add")
            return
        }
        let devices = try USBRegistry.attached()
        var rows = [["ID", "NAME", "STATE"]]
        for entry in config.entries {
            let attached = devices.first { $0.id.matches(entry.id) }
            let blocked = state?.blocked.first { $0.id == entry.id }
            let live: String
            if blocked != nil {
                live = entry.id.audioOnly ? "audio blocked" : "blocked"
            } else {
                live = attached == nil ? "not attached" : "waiting"
            }
            rows.append([entry.id.description, entry.name ?? attached?.name ?? blocked?.name ?? "-", live])
        }
        printTable(rows)
    }
}
