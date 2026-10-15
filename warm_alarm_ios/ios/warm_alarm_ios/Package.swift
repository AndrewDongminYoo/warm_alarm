// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "warm_alarm_ios",
    platforms: [
        .iOS("13.0"),
    ],
    products: [
        .library(name: "warm-alarm-ios", targets: ["warm_alarm_ios"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "warm_alarm_ios",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
        .testTarget(
            name: "warm_alarm_ios_tests",
            dependencies: ["warm_alarm_ios"]
        ),
    ]
)
