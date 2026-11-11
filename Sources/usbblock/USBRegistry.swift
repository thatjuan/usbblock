import Foundation
import IOKit
import USBBlockCore

/// An attached USB device instance, including interfaces that remain after capture.
struct AttachedDevice {
    let id: DeviceID
    let name: String
    let vendorName: String
    let location: UInt32
    let interfaceClasses: Set<Int>
    let isHub: Bool

    var interfaces: String {
        let labels = interfaceClasses.map { value in
            switch value {
            case 1: "audio"
            case 3: "hid"
            case 8: "storage"
            case 14: "video"
            case 2, 10: "network"
            case 224: "wireless"
            case 255: "vendor"
            default: "other"
            }
        }
        return Set(labels).sorted().joined(separator: ", ")
    }
}

/// Reads USB device properties without opening or claiming hardware.
enum USBRegistry {
    /// Enumerates attached instances, including captured devices and hubs.
    static func attached() throws -> [AttachedDevice] {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator)
        guard result == KERN_SUCCESS else { throw CLIError("Cannot enumerate USB devices: kern_return \(result)") }
        defer { IOObjectRelease(iterator) }
        var devices: [AttachedDevice] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let device = device(service) { devices.append(device) }
            IOObjectRelease(service)
        }
        return devices.sorted {
            if $0.vendorName != $1.vendorName { return $0.vendorName < $1.vendorName }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.location < $1.location
        }
    }

    /// Finds the owning device for an audio interface, or reads a device directly.
    static func blocked(_ service: io_service_t, audioOnly: Bool) -> DaemonState.Blocked? {
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        while IOObjectConformsTo(current, "IOUSBHostDevice") == 0 {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
            IOObjectRelease(current)
            current = parent
        }
        guard let device = device(current),
              let id = DeviceID(device.id.description + (audioOnly ? ":audio" : "")) else { return nil }
        return DaemonState.Blocked(id: id, name: device.name, location: device.location)
    }

    /// Builds one device row from its registry properties and interface classes.
    private static func device(_ service: io_service_t) -> AttachedDevice? {
        guard let vendor: Int = property(service, "idVendor"),
              let product: Int = property(service, "idProduct"),
              let id = DeviceID(String(format: "%04x:%04x", vendor, product)) else { return nil }
        var classes: Set<Int> = []
        var children: io_iterator_t = 0
        if IORegistryEntryGetChildIterator(service, kIOServicePlane, &children) == KERN_SUCCESS {
            defer { IOObjectRelease(children) }
            while case let child = IOIteratorNext(children), child != 0 {
                if IOObjectConformsTo(child, "IOUSBHostInterface") != 0,
                   let value: Int = property(child, "bInterfaceClass") {
                    classes.insert(value)
                }
                IOObjectRelease(child)
            }
        }
        return AttachedDevice(
            id: id,
            name: property(service, "USB Product Name") ?? property(service, "kUSBProductString") ?? "Unknown device",
            vendorName: property(service, "USB Vendor Name") ?? property(service, "kUSBVendorString") ?? "-",
            location: property(service, "locationID") ?? 0,
            interfaceClasses: classes,
            isHub: (property(service, "bDeviceClass") as Int?) == 9
        )
    }

    /// Reads a registry property as the requested Swift type.
    private static func property<T>(_ service: io_service_t, _ key: String) -> T? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? T
    }
}
