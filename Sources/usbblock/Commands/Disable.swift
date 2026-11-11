import ArgumentParser

/// Stops and removes the daemon while keeping saved rules and logs.
struct Disable: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop and remove the daemon, keeping the config.")

    /// Obtains root privileges and removes the daemon installation.
    func run() throws {
        try requireRoot()
        try LaunchDaemon.uninstall()
    }
}
