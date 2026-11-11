import ArgumentParser
import Foundation
import USBBlockCore

/// Adds or changes one blocking rule, with an interactive device picker.
struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Add a device to the block configuration.")

    @Argument(help: "Hex vendor:product[:audio]; omit to pick interactively.") var id: DeviceID?
    @Option(help: "Store this device name in the config.") var name: String?
    @Flag(help: "Allow blocking a whole device with keyboard/mouse interfaces.") var force = false

    /// Selects a device, checks whole-device HID safety, saves the rule and reloads.
    func run() throws {
        try checkPickerInput(id)
        try requireRoot()
        var config = try readConfig()
        let devices = try USBRegistry.attached()
        let interactive = id == nil
        let selectedID: DeviceID
        if let id {
            selectedID = id
        } else {
            let choices = devices.filter { !$0.isHub }
            printTable(choices.enumerated().map { [String($0.offset + 1), $0.element.id.description, $0.element.name, $0.element.interfaces] })
            let device = choices[try pickIndex(count: choices.count, question: "Block which device?")]
            if device.interfaceClasses.contains(1), device.interfaceClasses.contains(where: { $0 != 1 }) {
                let other = device.interfaces.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0 != "audio" }.joined(separator: ", ")
                let answer = try prompt("\(device.name) also has \(other). Block [a]udio only, or the [w]hole device?")
                guard ["a", "audio", "w", "whole"].contains(answer) else { throw CLIError("Choose 'a' or 'w'.") }
                selectedID = DeviceID(device.id.description + (["a", "audio"].contains(answer) ? ":audio" : ""))!
            } else {
                selectedID = device.id
            }
        }
        if config.entries.contains(where: { $0.id == selectedID }) {
            print("Already blocked: \(selectedID).")
            return
        }
        let device = devices.first { $0.id.matches(selectedID) }
        if !selectedID.audioOnly, !force,
           devices.contains(where: { $0.id.matches(selectedID) && $0.interfaceClasses.contains(3) }) {
            if interactive {
                print("\(selectedID) has keyboard/mouse interfaces. Blocking the whole device disables them, and the daemon keeps them blocked across reboots.")
                guard ["y", "yes"].contains(try prompt("Block it anyway? [y/N]")) else {
                    print("Cancelled.")
                    return
                }
            } else {
                throw CLIError("\(selectedID) has keyboard/mouse interfaces. Blocking the whole device disables them, and the daemon keeps them blocked across reboots. Pass --force if that's what you want.")
            }
        }
        let entry = Config.Entry(id: selectedID, name: name ?? device?.name)
        let result = config.upsert(entry)
        try writeConfig(config)
        if result == .modeChanged {
            let wholeID = String(format: "%04x:%04x", selectedID.vendor, selectedID.product)
            print("Changed \(wholeID) to \(selectedID.audioOnly ? "audio only" : "whole device").")
        } else {
            print("Added \(selectedID)\(entry.name.map { " (\($0))" } ?? "").")
        }
        try reloadDaemon()
    }
}
