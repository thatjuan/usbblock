import Foundation

/// A USB identity parsed from vendor:product[:audio], with 16-bit hexadecimal IDs.
public struct DeviceID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let vendor: Int
    public let product: Int
    /// Claim only USB Audio interfaces instead of capturing the whole device.
    public let audioOnly: Bool

    /// Parses vendor:product[:audio], rejecting malformed or out-of-range IDs.
    public init?(_ text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || (parts.count == 3 && parts[2] == "audio"),
              parts.prefix(2).allSatisfy({ part in
                  (1...4).contains(part.count) && part.utf8.allSatisfy {
                      (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
                  }
              }),
              let vendor = Int(parts[0], radix: 16), let product = Int(parts[1], radix: 16)
        else { return nil }
        self.vendor = vendor
        self.product = product
        self.audioOnly = parts.count == 3
    }

    public var description: String {
        String(format: "%04x:%04x", vendor, product) + (audioOnly ? ":audio" : "")
    }

    /// Compares vendor and product IDs regardless of blocking mode.
    public func matches(_ other: DeviceID) -> Bool {
        vendor == other.vendor && product == other.product
    }

    /// Decodes the same hex string accepted by the CLI and config file.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let id = DeviceID(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid device ID: \(text)")
        }
        self = id
    }

    /// Stores the canonical hex string, including the optional audio suffix.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
