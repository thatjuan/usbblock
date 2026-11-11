// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "usbblock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "usbblock",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("IOUSBHost")]
        ),
    ]
)
