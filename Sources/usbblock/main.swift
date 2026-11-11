// usbblock: keeps chosen USB devices, or just their audio, away from macOS.
//
// Whole devices are captured (the mechanism VM apps use for USB passthrough), which
// detaches every macOS driver from them, so e.g. a monitor's built-in audio never
// reaches CoreAudio. Root can capture without the com.apple.vm.device-access
// entitlement. When this process exits, macOS resets the devices and they come back.
//
// With ":audio", only the device's USB Audio interfaces are claimed, so a camera keeps
// its video but loses its mic. Those interfaces are held open by usbaudiod, which
// ignores close requests, so we kill it and open them in the moment before launchd
// respawns it.
//
// macOS 27's userspace USB audio driver (usbaudiod) doesn't notice when its clients
// are torn down or released, so CoreAudio keeps a stale view either way. We restart it
// after claiming and again on exit; launchd respawns it and it rescans.
//
// Usage: sudo usbblock <vendor:product[:audio]> [...]   (hex IDs, e.g. 043e:9a4b)

import Foundation
import IOKit
import IOUSBHost

/// A USB device identity, parsed from "vvvv:pppp" or "vvvv:pppp:audio" hex.
struct DeviceID: CustomStringConvertible {
    let vendor: Int
    let product: Int
    /// Claim only the device's USB Audio interfaces instead of the whole device.
    let audioOnly: Bool

    init?(_ text: String) {
        let parts = text.split(separator: ":")
        guard parts.count == 2 || (parts.count == 3 && parts[2] == "audio"),
              let vendor = Int(parts[0], radix: 16),
              let product = Int(parts[1], radix: 16)
        else { return nil }
        self.vendor = vendor
        self.product = product
        self.audioOnly = parts.count == 3
    }

    var description: String { String(format: "%04x:%04x", vendor, product) + (audioOnly ? ":audio" : "") }
}

/// kIOMessageServiceIsTerminated; the C macro doesn't import into Swift.
let serviceTerminated: UInt32 = 0xE000_0010
/// bInterfaceClass for USB Audio.
let audioInterfaceClass = 1

func log(_ message: String) {
    let stamp = Date().formatted(.iso8601)
    FileHandle.standardError.write(Data("\(stamp) \(message)\n".utf8))
}

/// Kills usbaudiod; launchd respawns it within milliseconds.
func killUSBAudio() {
    let killall = Process()
    killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    killall.arguments = ["-9", "usbaudiod"]
    try? killall.run()
    killall.waitUntilExit()
}

/// Watches for matching devices and interfaces and holds a claim on each one.
/// All state is touched only on `queue`.
final class Blocker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "usbblock")
    private let port: IONotificationPortRef
    private var iterators: [io_iterator_t] = []
    private var captured: [UInt64: IOUSBHostDevice] = [:]
    private var claimed: [UInt64: IOUSBHostInterface] = [:]
    /// Audio interfaces usbaudiod got to first; retained until claimed or gone.
    private var pending: [UInt64: io_service_t] = [:]
    private var pendingAudioRestart: DispatchWorkItem?
    private var restartAttempts = 0

    init() {
        port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, queue)
    }

    func watch(_ ids: [DeviceID]) {
        queue.async { ids.forEach(self.addMatching) }
    }

    /// Releases claimed interfaces and restarts usbaudiod so it picks them up again.
    /// Captured devices need nothing: macOS resets them when this process exits.
    func releaseInterfaces() {
        queue.sync {
            guard !claimed.isEmpty else { return }
            claimed.values.forEach { $0.destroy() }
            claimed.removeAll()
            killUSBAudio()
        }
    }

    private func addMatching(_ id: DeviceID) {
        let matching: NSMutableDictionary
        if id.audioOnly {
            // IOUSBHostInterface only matches certain key combinations directly;
            // IOPropertyMatch sidesteps that.
            matching = IOServiceMatching("IOUSBHostInterface") as NSMutableDictionary
            matching["IOPropertyMatch"] = ["idVendor": id.vendor, "idProduct": id.product]
        } else {
            matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
            matching["idVendor"] = id.vendor
            matching["idProduct"] = id.product
        }

        var iterator: io_iterator_t = 0
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = id.audioOnly
            ? { context, iterator in Unmanaged<Blocker>.fromOpaque(context!).takeUnretainedValue().drainInterfaces(iterator) }
            : { context, iterator in Unmanaged<Blocker>.fromOpaque(context!).takeUnretainedValue().drainDevices(iterator) }
        let result = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching, callback, context, &iterator)
        guard result == KERN_SUCCESS else {
            log("cannot watch \(id): kern_return \(result)")
            return
        }
        iterators.append(iterator)
        log("watching \(id)")
        // Draining arms the notification and picks up what is already attached.
        id.audioOnly ? drainInterfaces(iterator) : drainDevices(iterator)
    }

    /// Captures each device once it finishes enumerating. Capturing a device that is
    /// still being configured (e.g. a display waking up) lets macOS publish its
    /// remaining interfaces anyway, and usbaudiod attaches to them.
    private func drainDevices(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            DispatchQueue.global().async { [self] in
                var timeout = mach_timespec_t(tv_sec: 10, tv_nsec: 0)
                IOServiceWaitQuiet(service, &timeout)
                queue.async {
                    self.capture(service)
                    IOObjectRelease(service)
                }
            }
        }
    }

    private func drainInterfaces(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            if property(service, "bInterfaceClass") == audioInterfaceClass, !claim(service) {
                // usbaudiod holds it; claim it during the next usbaudiod restart.
                IOObjectRetain(service)
                pending[entryID(service)] = service
            }
            IOObjectRelease(service)
        }
        if !pending.isEmpty { scheduleAudioRestart() }
    }

    private func capture(_ service: io_service_t) {
        let id = entryID(service)
        let label = describe(service)
        do {
            let device = try IOUSBHostDevice(__ioService: service, options: [.deviceCapture], queue: queue) { [weak self] _, message, _ in
                guard message == serviceTerminated else { return }
                // Unplugged, or the display went to sleep; a new device will match on return.
                self?.captured.removeValue(forKey: id)?.destroy()
                log("released \(label) (device went away)")
            }
            captured[id] = device
            log("captured \(label)")
            // Drivers that reattach do so within seconds (usbaudiod restarts after 5s).
            IOObjectRetain(service)
            queue.asyncAfter(deadline: .now() + 15) { [self] in
                defer { IOObjectRelease(service) }
                guard captured[id] != nil else { return }
                let attached = driverCount(service)
                if attached > 0 { log("warning: \(label) still has drivers on \(attached) interface(s)") }
            }
            scheduleAudioRestart()
        } catch {
            log("failed to capture \(label): \(error.localizedDescription)")
        }
    }

    /// Opens an interface exclusively; returns false while another client holds it.
    private func claim(_ service: io_service_t) -> Bool {
        let id = entryID(service)
        let number: Int = property(service, "bInterfaceNumber") ?? -1
        let label = describe(service) + " interface \(number)"
        guard let interface = try? IOUSBHostInterface(__ioService: service, options: [], queue: queue, interestHandler: { [weak self] _, message, _ in
            guard message == serviceTerminated else { return }
            self?.claimed.removeValue(forKey: id)?.destroy()
            log("released \(label) (device went away)")
        }) else { return false }
        claimed[id] = interface
        log("claimed \(label)")
        return true
    }

    /// Restarts usbaudiod once claims settle, so a burst of them costs one restart.
    /// Devices behind one display or hub can arrive seconds apart, and launchd won't
    /// respawn usbaudiod twice within 10s, so the wait is generous.
    /// Pending interfaces are claimed in the gap before launchd respawns it.
    private func scheduleAudioRestart() {
        pendingAudioRestart?.cancel()
        let work = DispatchWorkItem { [self] in
            log("restarting usbaudiod so CoreAudio drops claimed devices")
            killUSBAudio()
            let deadline = Date().addingTimeInterval(5)
            while !pending.isEmpty, Date() < deadline {
                for (id, service) in pending where claim(service) {
                    IOObjectRelease(service)
                    pending.removeValue(forKey: id)
                }
                usleep(2_000)
            }
            guard !pending.isEmpty else { restartAttempts = 0; return }
            restartAttempts += 1
            if restartAttempts < 3 {
                log("usbaudiod reclaimed \(pending.count) interface(s), retrying")
                scheduleAudioRestart()
            } else {
                log("giving up on \(pending.count) interface(s) after \(restartAttempts) usbaudiod restarts")
                pending.values.forEach { IOObjectRelease($0) }
                pending.removeAll()
                restartAttempts = 0
            }
        }
        pendingAudioRestart = work
        queue.asyncAfter(deadline: .now() + 5, execute: work)
    }

    /// Interfaces of a device that have a driver or client attached. Capture leaves the
    /// interfaces published but bare, so this is 0 when the device is truly hidden.
    private func driverCount(_ service: io_service_t) -> Int {
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &children) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(children) }
        var count = 0
        while case let child = IOIteratorNext(children), child != 0 {
            var grandchild: io_registry_entry_t = 0
            if IOObjectConformsTo(child, "IOUSBHostInterface") != 0,
               IORegistryEntryGetChildEntry(child, kIOServicePlane, &grandchild) == KERN_SUCCESS {
                count += 1
                IOObjectRelease(grandchild)
            }
            IOObjectRelease(child)
        }
        return count
    }

    private func entryID(_ service: io_service_t) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &id)
        return id
    }

    private func property<T>(_ service: io_service_t, _ key: String) -> T? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? T
    }

    private func describe(_ service: io_service_t) -> String {
        let name: String = property(service, "USB Product Name") ?? property(service, "kUSBProductString") ?? "unknown"
        let location: Int = property(service, "locationID") ?? 0
        return String(format: "%@ @ 0x%08x", name, location)
    }
}

let ids = CommandLine.arguments.dropFirst().map { arg in
    guard let id = DeviceID(arg) else {
        log("invalid device id '\(arg)', expected vendor:product[:audio] in hex (e.g. 043e:9a4b)")
        exit(64)
    }
    return id
}
guard !ids.isEmpty else {
    log("usage: usbblock <vendor:product[:audio]> [...]")
    exit(64)
}
guard getuid() == 0 else {
    log("usbblock must run as root to capture devices")
    exit(77)
}

let blocker = Blocker()
blocker.watch(ids)

// Exit cleanly on SIGTERM/SIGINT so devices and interfaces are handed back to macOS.
let signalSources = [SIGTERM, SIGINT].map { sig in
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
    source.setEventHandler { @Sendable in
        log("exiting, releasing devices")
        blocker.releaseInterfaces()
        exit(0)
    }
    source.resume()
    return source
}

dispatchMain()
