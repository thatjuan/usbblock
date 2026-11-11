// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "usbblock",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "USBBlockCore"),
        .executableTarget(
            name: "usbblock",
            dependencies: ["USBBlockCore", .product(name: "ArgumentParser", package: "swift-argument-parser")],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("IOUSBHost")]
        ),
        .testTarget(name: "USBBlockCoreTests", dependencies: ["USBBlockCore"]),
    ]
)
