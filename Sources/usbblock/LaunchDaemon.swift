import Foundation
import USBBlockCore

/// Installs the stable binary and launchd job; configuration survives uninstalling.
enum LaunchDaemon {
    static let path = "/Library/LaunchDaemons/com.thatjuan.usbblock.plist"
    static let binaryPath = "/usr/local/libexec/usbblock"
    static let label = "com.thatjuan.usbblock"
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: path) }

    /// Imports only a legacy job's ID arguments, before replacing its plist.
    static func migrateConfig() throws {
        guard !FileManager.default.fileExists(atPath: Config.path), isInstalled else { return }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let job = plist as? [String: Any], let arguments = job["ProgramArguments"] as? [String] else { return }
        let ids = Config.importingLegacyArguments(arguments)
        guard !ids.isEmpty else { return }
        var config = Config()
        for id in ids { config.upsert(.init(id: id)) }
        try writeConfig(config)
        print("Imported \(config.entries.count) devices from the previous install.")
    }

    static func install() throws {
        try FileManager.default.createDirectory(atPath: "/usr/local/libexec", withIntermediateDirectories: true)
        try writeAtomic(Data(contentsOf: URL(fileURLWithPath: executablePath())), to: binaryPath, mode: 0o755)
        try migrateConfig()
        let config = try readConfig()
        // Create even an empty config so its path is ready for manual edits.
        if !FileManager.default.fileExists(atPath: Config.path) { try writeConfig(config) }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binaryPath, "run"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardErrorPath": "/var/log/usbblock.log",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try writeAtomic(data, to: path, mode: 0o644)
        try launchctl(["bootout", "system", path], ignoreFailure: true)
        try launchctl(["bootstrap", "system", path])
        print("Installed \(binaryPath) (\(usbblockVersion)).")
        print("Daemon started. Blocking \(config.entries.count) devices from \(Config.path).")
        if config.entries.isEmpty { print("No devices configured yet. Add some with: sudo usbblock add") }
    }

    static func uninstall() throws {
        try launchctl(["bootout", "system", path], ignoreFailure: true)
        for file in [path, binaryPath, DaemonState.path] where FileManager.default.fileExists(atPath: file) {
            try FileManager.default.removeItem(atPath: file)
        }
        print("Daemon disabled. Blocked devices are back. Configuration kept at \(Config.path).")
    }

    static func reload() throws {
        try launchctl(["kickstart", "-k", "system/\(label)"])
    }

    private static func launchctl(_ arguments: [String], ignoreFailure: Bool = false) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        if ignoreFailure {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 && !ignoreFailure {
            throw CLIError("launchctl \(arguments.joined(separator: " ")) failed (exit \(process.terminationStatus)); check `usbblock logs`.")
        }
    }
}
