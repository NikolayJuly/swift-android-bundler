// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "foundation-extension",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FoundationExtension",
            targets: [
                "FileSystemKit",
                "FoundationExtension",
                "LoggingExtension",
            ]
        ),
        .library(
            name: "ShellKit",
            targets: ["ShellKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
    ],
    targets: [

        // MARK: FileSystemKit

        .target(name: "FileSystemKit",
                dependencies: [
                    "FoundationExtension",
                    "LoggingExtension",
                    .product(name: "Logging", package: "swift-log"),
                ]),

        // MARK: FoundationExtension

        .target(name: "FoundationExtension",
                dependencies: [
                    "LoggingExtension",
                    .product(name: "Logging", package: "swift-log"),
                ]),

        // MARK: LoggingExtension

        .target(name: "LoggingExtension",
                dependencies: [
                    .product(name: "Logging", package: "swift-log"),
                ]),

        // MARK: ShellKit

        .target(name: "ShellKit",
                dependencies: [
                    .product(name: "Logging", package: "swift-log"),
                ]),

    ]
)
