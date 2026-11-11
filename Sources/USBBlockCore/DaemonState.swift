import Foundation

/// Public snapshot of the captures and audio claims held by one daemon process.
public struct DaemonState: Codable, Equatable {
    public static let path = "/var/run/usbblock.json"
    public var pid: Int32
    public var version: String
    public var started: Date
    public var blocked: [Blocked]

    /// One blocked device instance, identified by rule and bus location.
    public struct Blocked: Codable, Hashable {
        public var id: DeviceID
        public var name: String
        public var location: UInt32

        public init(id: DeviceID, name: String, location: UInt32) {
            self.id = id
            self.name = name
            self.location = location
        }
    }

    public init(pid: Int32, version: String, started: Date, blocked: [Blocked]) {
        self.pid = pid
        self.version = version
        self.started = started
        self.blocked = blocked
    }
}
