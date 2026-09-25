// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "dinky",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", exact: "0.4.4"),
    ],
    targets: [
        // Private SkyLight and CGS calls. Objective-C, capability checked, nothing else lives here.
        .target(
            name: "DinkyPrivate",
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "SkyLight"]),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
            ]
        ),
        // Pure layout engine: trees, rectangles, no AppKit. Fully unit tested.
        .target(
            name: "DinkyLayout",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DinkyLayoutTests",
            dependencies: ["DinkyLayout"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Config types and TOML loading. No AppKit. Unit tested.
        .target(
            name: "DinkyConfig",
            dependencies: [.product(name: "TOMLDecoder", package: "TOMLDecoder")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DinkyConfigTests",
            dependencies: ["DinkyConfig"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The app and CLI.
        .executableTarget(
            name: "dinky",
            dependencies: ["DinkyPrivate", "DinkyLayout", "DinkyConfig"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
