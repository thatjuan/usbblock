import ArgumentParser

struct Enable: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Install this version and start the daemon.")

    func run() throws {
        try requireRoot()
        try LaunchDaemon.install()
    }
}
