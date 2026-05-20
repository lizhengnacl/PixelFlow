// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PixelFlow",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PixelFlow", targets: ["PixelFlow"])
    ],
    targets: [
        .executableTarget(
            name: "PixelFlow",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
