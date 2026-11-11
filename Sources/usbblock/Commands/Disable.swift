import ArgumentParser

struct Disable: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop and remove the daemon, keeping the config.")

    func run() throws {
        try requireRoot()
        try LaunchDaemon.uninstall()
    }
}
