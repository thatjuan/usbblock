import ArgumentParser
import Darwin
import Foundation
import USBBlockCore

/// Entry point for device selection, blocking and daemon management.
@main
struct USBBlock: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "usbblock",
        abstract: "Hide chosen USB devices, or just their audio, from macOS.",
        discussion: """
            Whole-device capture detaches every driver from a matching USB device.
            Audio-only rules claim USB Audio interfaces and keep other functions available.
            Blocking restarts usbaudiod, which briefly interrupts other USB audio.
            Use add to save rules, then enable to block across replugs, sleep and reboots.
            The daemon runs as root; disable stops it and restores blocked devices.
            """,
        version: usbblockVersion,
        subcommands: [List.self, Add.self, Remove.self, Status.self, Enable.self, Disable.self, Logs.self, Run.self]
    )
}

extension DeviceID: ExpressibleByArgument {
    public init?(argument: String) { self.init(argument) }
}

/// User-facing command failure; ArgumentParser reports it with exit status 1.
struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Reads saved rules; a missing config means no devices are blocked.
func readConfig() throws -> Config {
    do {
        return try Config(parsing: String(contentsOfFile: Config.path, encoding: .utf8))
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        return Config()
    }
}

/// Saves rules atomically with root ownership and readable permissions.
func writeConfig(_ config: Config) throws {
    try writeAtomic(Data(config.formatted().utf8), to: Config.path, mode: 0o644)
}

/// A stale or unreadable snapshot never marks a device blocked.
func runningState() -> DaemonState? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: DaemonState.path)),
          let state = try? JSONDecoder().decode(DaemonState.self, from: data), state.pid > 0,
          kill(state.pid, 0) == 0 || errno == EPERM else { return nil }
    return state
}

/// Prints rows with aligned columns sized to their widest cell.
func printTable(_ rows: [[String]]) {
    guard let first = rows.first else { return }
    let widths = first.indices.map { column in rows.map { $0[column].count }.max() ?? 0 }
    for row in rows {
        print(row.enumerated().map { column, cell in
            column == widths.count - 1 ? cell : cell.padding(toLength: widths[column] + 2, withPad: " ", startingAt: 0)
        }.joined())
    }
}

/// The no-ID/non-TTY error is checked before sudo, so pipes never request a password.
func checkPickerInput(_ id: DeviceID?) throws {
    if id == nil && isatty(STDIN_FILENO) == 0 {
        throw CLIError("pass a device ID; see `usbblock list`")
    }
}

/// Reads a trimmed, lowercase reply from the interactive terminal.
func prompt(_ text: String) throws -> String {
    print(text, terminator: " ")
    fflush(stdout)
    guard let answer = readLine() else { throw CLIError("No selection made.") }
    return answer.trimmingCharacters(in: .whitespaces).lowercased()
}

/// Converts a one-based menu choice into a checked array index.
func pickIndex(count: Int, question: String) throws -> Int {
    guard count > 0 else { throw CLIError("No devices to choose from.") }
    guard let number = Int(try prompt(question)), (1...count).contains(number) else {
        throw CLIError("Choose a number from 1 to \(count).")
    }
    return number - 1
}

/// Reloads an installed job after rule changes, or explains how to start one.
func reloadDaemon() throws {
    if LaunchDaemon.isInstalled {
        try LaunchDaemon.reload()
        print("Daemon reloaded.")
    } else {
        print("The daemon isn't running. Start it with: sudo usbblock enable")
    }
}
