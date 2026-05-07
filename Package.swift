// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DiskFerry",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DiskFerry", targets: ["DiskFerry"])
    ],
    targets: [
        .executableTarget(
            name: "DiskFerry",
            path: "Sources/DiskFerry"
        )
    ]
)
