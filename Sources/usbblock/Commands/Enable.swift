import ArgumentParser

/// Installs this version as a launchd daemon and starts blocking saved rules.
struct Enable: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Install this version and start the daemon.")

    /// Obtains root privileges and installs or replaces the daemon.
    func run() throws {
        try requireRoot()
        try LaunchDaemon.install()
    }
}
