// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "idd-softwareupdate",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "IDDSoftwareUpdate",
            targets: ["IDDSoftwareUpdate"]
        )
    ],
    dependencies: [
        // .package(name: "idd-alert", path: "../idd-alert"),
        .package(url: "https://github.com/kdeda/idd-alert.git", "2.0.1" ..< "3.0.0"),
        // .package(name: "idd-swift", path: "../idd-swift"),
        .package(url: "https://github.com/kdeda/idd-swift.git", "2.3.2" ..< "3.0.0"),
        .package(url: "https://github.com/kdeda/idd-swiftui.git", "2.1.2" ..< "3.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "IDDSoftwareUpdate",
            dependencies: [
                .product(name: "IDDAlert", package: "idd-alert"),
                .product(name: "IDDSwiftUI", package: "idd-swiftui"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .testTarget(
            name: "IDDSoftwareUpdateTests",
            dependencies: [
                "IDDSoftwareUpdate"
            ]
        )
    ]
)
