// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CronBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "CronBar",
            path: "Sources/CronBar",
            resources: [
                .copy("Resources/AppIcon.png")
            ]
        )
    ]
)
