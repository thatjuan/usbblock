import ArgumentParser
import USBBlockCore

struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Remove a device from the block configuration.")

    @Argument(help: "Hex vendor:product[:audio]; omit to pick a configured entry.") var id: DeviceID?

    func run() throws {
        try checkPickerInput(id)
        try requireRoot()
        var config = try readConfig()
        let selectedID: DeviceID
        if let id {
            selectedID = id
        } else {
            printTable(config.entries.enumerated().map { [String($0.offset + 1), $0.element.id.description, $0.element.name ?? "-"] })
            selectedID = config.entries[try pickIndex(count: config.entries.count, question: "Unblock which device?")].id
        }
        guard let removed = config.remove(vendor: selectedID.vendor, product: selectedID.product) else {
            throw CLIError("\(selectedID) is not configured.")
        }
        try writeConfig(config)
        print("Removed \(removed.id)\(removed.name.map { " (\($0))" } ?? "").")
        try reloadDaemon()
    }
}
