// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NotePop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NotePop", targets: ["NotePop"])
    ],
    targets: [
        .executableTarget(
            name: "NotePop",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
