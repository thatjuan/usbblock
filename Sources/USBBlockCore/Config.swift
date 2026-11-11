import Foundation

/// A config parse failure, including the original one-based line number.
public struct ConfigError: Error, Equatable, CustomStringConvertible {
    public let line: Int
    public let text: String
    public var description: String {
        "usbblock.conf:\(line): invalid device id '\(text)', expected vendor:product[:audio] in hex"
    }
}

/// Ordered block rules and optional device names from usbblock.conf.
public struct Config: Equatable {
    /// One blocking rule and its optional human-readable name.
    public struct Entry: Equatable {
        public var id: DeviceID
        public var name: String?

        public init(id: DeviceID, name: String? = nil) {
            self.id = id
            self.name = name
        }
    }

    public static let path = "/etc/usbblock.conf"
    public var entries: [Entry]

    public init(entries: [Entry] = []) { self.entries = entries }

    /// Parses hex IDs and optional names after #, preserving line numbers on errors.
    public init(parsing text: String) throws(ConfigError) {
        entries = []
        for (offset, line) in text.components(separatedBy: "\n").enumerated() {
            let parts = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            let token = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            guard let id = DeviceID(token) else { throw ConfigError(line: offset + 1, text: token) }
            let name = parts.count == 2 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            entries.append(Entry(id: id, name: name.isEmpty ? nil : name))
        }
    }

    /// Serializes rules with a help header and one optional name comment per line.
    public func formatted() -> String {
        let header = "# usbblock devices. Edit with `sudo usbblock add` / `sudo usbblock remove`,\n# or by hand and then `sudo usbblock enable` to reload.\n"
        return header + entries.map { entry in
            // Keep a supplied name on one comment line, including names containing '#'.
            let name = entry.name?.components(separatedBy: .newlines).joined(separator: " ")
            return entry.id.description + (name.map { "   # \($0)" } ?? "") + "\n"
        }.joined()
    }

    /// Describes whether adding a rule inserted it, kept it or changed its mode.
    public enum UpsertResult: Equatable { case added, unchanged, modeChanged }

    /// Replaces a device's mode in place; repeated additions leave its name untouched.
    @discardableResult
    public mutating func upsert(_ entry: Entry) -> UpsertResult {
        guard let index = entries.firstIndex(where: { $0.id.matches(entry.id) }) else {
            entries.append(entry)
            return .added
        }
        guard entries[index].id != entry.id else { return .unchanged }
        entries[index] = entry
        return .modeChanged
    }

    /// Removes a device regardless of its configured blocking mode.
    @discardableResult
    public mutating func remove(vendor: Int, product: Int) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.id.vendor == vendor && $0.id.product == product }) else { return nil }
        let entry = entries[index]
        entries.removeAll { $0.id.vendor == vendor && $0.id.product == product }
        return entry
    }

    /// Extracts pre-CLI rules, ignoring the executable and non-ID arguments.
    public static func importingLegacyArguments(_ arguments: [String]) -> [DeviceID] {
        arguments.dropFirst().compactMap(DeviceID.init)
    }
}
