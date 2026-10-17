// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "warm_alarm_macos",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "warm-alarm-macos", targets: ["warm_alarm_macos"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "warm_alarm_macos",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
        .testTarget(
            name: "warm_alarm_macos_tests",
            dependencies: ["warm_alarm_macos"]
        )
    ]
)
