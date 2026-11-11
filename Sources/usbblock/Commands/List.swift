import ArgumentParser

/// Lists attached USB device instances and their live blocking state.
struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List attached USB device instances.")

    @Flag(help: "Include USB hubs.") var all = false

    /// Joins registry devices to daemon state, hiding hubs unless requested.
    func run() throws {
        let state = runningState()
        let devices = try USBRegistry.attached().filter { all || !$0.isHub }
        var rows = [["ID", "NAME", "VENDOR", "INTERFACES", "STATUS"]]
        for device in devices {
            let blocked = state?.blocked.first { $0.id.matches(device.id) && $0.location == device.location }
            rows.append([device.id.description, device.name, device.vendorName,
                         device.interfaces.isEmpty ? "-" : device.interfaces,
                         blocked.map { $0.id.audioOnly ? "audio blocked" : "blocked" } ?? "-"])
        }
        printTable(rows)
    }
}
