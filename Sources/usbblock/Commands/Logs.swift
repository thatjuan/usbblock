import ArgumentParser
import Foundation

struct Logs: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Read the daemon log, optionally following it.")

    @Option(name: [.short, .long], help: "Number of lines to show.") var n = 50
    @Flag(name: [.short, .long], help: "Follow new log messages.") var follow = false

    func validate() throws {
        guard n >= 0 else { throw ValidationError("Line count must be non-negative.") }
    }

    func run() throws {
        let path = "/var/log/usbblock.log"
        guard FileManager.default.fileExists(atPath: path) else {
            print("No log yet; is the daemon enabled?")
            return
        }
        try replaceProcess("/usr/bin/tail", arguments: ["-n", String(n)] + (follow ? ["-f"] : []) + [path])
    }
}
