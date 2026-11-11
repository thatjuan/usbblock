import Foundation
import Testing
@testable import USBBlockCore

@Test(arguments: ["043e:9a4b", "043E:9A4B", "046d:082d:audio"])
func deviceIDRoundTrips(_ text: String) throws {
    let id = try #require(DeviceID(text))
    #expect(DeviceID(id.description) == id)
    #expect(id.description == text.lowercased())
}

@Test(arguments: ["043e", "043e:9a4b:video", "zzzz:0000", "043e:9a4b:audio:x", "043e::9a4b", "10000:0000", "-001:0000", ":0000"])
func invalidDeviceID(_ text: String) {
    #expect(DeviceID(text) == nil)
}

@Test func configParsesCommentsAndNames() throws {
    let config = try Config(parsing: "# devices\n\n043E:9A4B # LG UltraFine Display Audio\n046d:082d:audio\n")
    #expect(config.entries == [
        .init(id: try #require(DeviceID("043e:9a4b")), name: "LG UltraFine Display Audio"),
        .init(id: try #require(DeviceID("046d:082d:audio"))),
    ])
    #expect(try Config(parsing: config.formatted()) == config)
}

@Test func configReportsBadLine() {
    do {
        _ = try Config(parsing: "# devices\n\nxyz\n")
        Issue.record("Expected an invalid config error")
    } catch {
        #expect(error.line == 3)
        #expect(error.description == "usbblock.conf:3: invalid device id 'xyz', expected vendor:product[:audio] in hex")
    }
}

@Test func configHandlesWindowsLineEndings() throws {
    let config = try Config(parsing: "# devices\r\n043e:9a4b # LG UltraFine Display Audio\r\n")
    #expect(config.entries.count == 1)
    do {
        _ = try Config(parsing: "# devices\r\n\r\nxyz\r\n")
        Issue.record("Expected an invalid config error")
    } catch {
        #expect(error.line == 3)
    }
}

@Test func configUpsertsInPlaceAndRemovesEitherMode() throws {
    let display = Config.Entry(id: try #require(DeviceID("043e:9a4b")), name: "LG UltraFine Display Audio")
    let camera = Config.Entry(id: try #require(DeviceID("046d:082d")), name: "HD Pro Webcam C920")
    let audio = Config.Entry(id: try #require(DeviceID("046d:082d:audio")), name: camera.name)
    let receiver = Config.Entry(id: try #require(DeviceID("046d:c52b")), name: "USB Receiver")
    var config = Config()
    #expect(config.upsert(display) == .added)
    #expect(config.upsert(camera) == .added)
    #expect(config.upsert(receiver) == .added)
    #expect(config.upsert(camera) == .unchanged)
    #expect(config.upsert(audio) == .modeChanged)
    #expect(config.entries == [display, audio, receiver])
    #expect(config.remove(vendor: camera.id.vendor, product: camera.id.product) == audio)
    #expect(config.entries == [display, receiver])
    #expect(config.remove(vendor: camera.id.vendor, product: camera.id.product) == nil)
    #expect(try Config(parsing: config.formatted()) == config)
    #expect(try Config(parsing: Config().formatted()) == Config())
}

@Test func importsLegacyArguments() throws {
    let arguments = ["/usr/local/libexec/usbblock", "043E:9A4B", "--invalid", "046d:082d:audio", "xyz"]
    #expect(Config.importingLegacyArguments(arguments) == [
        try #require(DeviceID("043e:9a4b")), try #require(DeviceID("046d:082d:audio")),
    ])
    #expect(Config.importingLegacyArguments(["043e:9a4b"]).isEmpty)
}

@Test func daemonStateEncodesIDAsString() throws {
    let id = try #require(DeviceID("046d:082d:audio"))
    let state = DaemonState(pid: 412, version: "0.1.0", started: Date(timeIntervalSince1970: 0), blocked: [
        .init(id: id, name: "HD Pro Webcam C920", location: 1),
    ])
    let data = try JSONEncoder().encode(state)
    #expect(String(decoding: data, as: UTF8.self).contains("\"id\":\"046d:082d:audio\""))
    #expect(try JSONDecoder().decode(DaemonState.self, from: data) == state)
}
