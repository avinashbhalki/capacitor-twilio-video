// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "CapacitorTwilioVideo",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "CapacitorTwilioVideo",
            targets: ["TwilioVideoPlugin"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", branch: "main"),
        .package(url: "https://github.com/twilio/twilio-video-ios", .exact("5.8.2"))
    ],
    targets: [
        .target(
            name: "TwilioVideoPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "TwilioVideo", package: "twilio-video-ios")
            ],
            path: "ios/Plugin",
            sources: ["TwilioVideoPlugin.swift", "VideoCallViewController.swift"],
            publicHeadersPath: "."
        )
    ]
)
