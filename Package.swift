// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "dinky",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "DinkyPrivate",
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "SkyLight"]),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "dinky",
            dependencies: ["DinkyPrivate"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
