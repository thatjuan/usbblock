import ArgumentParser
import Darwin
import Foundation
import USBBlockCore

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Block devices in the foreground; Ctrl-C releases them.")

    @Argument(help: "Block exactly these IDs, or use the config if omitted.") var ids: [DeviceID] = []

    func run() throws {
        try requireRoot()
        let selected: [DeviceID]
        do {
            selected = ids.isEmpty ? try readConfig().entries.map(\.id) : ids
        } catch {
            log(String(describing: error))
            throw error
        }
        let blocker = Blocker()
        if selected.isEmpty { log("no devices configured; waiting") }
        blocker.watch(selected)

        // Exit cleanly on SIGTERM/SIGINT so devices and interfaces are handed back to macOS.
        let signalSources = [SIGTERM, SIGINT].map { sig in
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler { @Sendable in
                log("exiting, releasing devices")
                blocker.releaseInterfaces()
                Darwin.exit(0)
            }
            source.resume()
            return source
        }
        withExtendedLifetime(signalSources) { dispatchMain() }
    }
}
