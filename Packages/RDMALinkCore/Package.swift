// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RDMALinkCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "RDMALinkCore", targets: ["RDMALinkCore"]),
        .executable(name: "rdmalink", targets: ["rdmalink"]),
    ],
    targets: [
        .target(
            name: "RDMALinkCore",
            linkerSettings: [
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(name: "rdmalink", dependencies: ["RDMALinkCore"]),
        .testTarget(name: "RDMALinkCoreTests", dependencies: ["RDMALinkCore"]),
    ],
    swiftLanguageModes: [.v6]
)
