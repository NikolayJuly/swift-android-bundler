// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "swift-android-bundler",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "swift-android-bundler", targets: ["SwiftAndroidBundler"]),
    ],
    dependencies: [
        .package(path: "Dependencies/FoundationExtension"),

        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/NikolayJuly/drain-work-pool.git", from: "4.0.0"),
    ],
    targets: [
        // MARK: - Libraries

        .target(name: "AndroidTestKit",
                dependencies: [
                    "DependencyCollector",
                    "SharedStructs",
                    "SwiftAndroidBuilder",
                    .product(name: "FoundationExtension", package: "FoundationExtension"),
                    .product(name: "Logging", package: "swift-log"),
                    .product(name: "ShellKit", package: "FoundationExtension"),
                ]),
        .target(name: "DependencyCollector",
                dependencies: [
                    "SharedStructs",
                    .product(name: "FoundationExtension", package: "FoundationExtension"),
                    .product(name: "Logging", package: "swift-log"),
                    .product(name: "ShellKit", package: "FoundationExtension"),
                ]),
        .target(name: "DependencyGraph",
                dependencies: [
                    "SharedStructs",
                    .product(name: "FoundationExtension", package: "FoundationExtension"),
                    .product(name: "Logging", package: "swift-log"),
                    .product(name: "ShellKit", package: "FoundationExtension"),
                    .product(name: "WorkPoolDraining", package: "drain-work-pool"),
                ]),
        .target(name: "EnvironmentSetup",
                dependencies: [
                    "SharedStructs",
                    .product(name: "FoundationExtension", package: "FoundationExtension"),
                    .product(name: "Logging", package: "swift-log"),
                    .product(name: "ShellKit", package: "FoundationExtension"),
                ]),
        .target(name: "FoundationDependencyAnalyzer",
                dependencies: [
                    "SharedStructs",
                    .product(name: "FoundationExtension", package: "FoundationExtension"),
                    .product(name: "Logging", package: "swift-log"),
                    .product(name: "ShellKit", package: "FoundationExtension"),
                    .product(name: "WorkPoolDraining", package: "drain-work-pool"),
                ]),
        .target(name: "SwiftAndroidBuilder",
                dependencies: [
                    "DependencyGraph",
                    "FoundationDependencyAnalyzer",
                    "SharedStructs",
                    .product(name: "FoundationExtension", package: "FoundationExtension"),
                    .product(name: "Logging", package: "swift-log"),
                    .product(name: "ShellKit", package: "FoundationExtension"),
                ]),
        .target(name: "SharedStructs",
                dependencies: [
                    .product(name: "FoundationExtension", package: "FoundationExtension"),
                    .product(name: "Logging", package: "swift-log"),
                    .product(name: "ShellKit", package: "FoundationExtension"),
                ]),

        // MARK: - Executables

        .executableTarget(name: "SwiftAndroidBundler",
                          dependencies: [
                              "AndroidTestKit",
                              "DependencyCollector",
                              "EnvironmentSetup",
                              "SharedStructs",
                              "SwiftAndroidBuilder",
                              .product(name: "ArgumentParser", package: "swift-argument-parser"),
                              .product(name: "FoundationExtension", package: "FoundationExtension"),
                              .product(name: "Logging", package: "swift-log"),
                          ]),

        // MARK: - Tests

        .testTarget(name: "AndroidTestKitTests",
                     dependencies: [
                         "AndroidTestKit",
                         "DependencyCollector",
                         "SharedStructs",
                         "SwiftAndroidBuilder",
                         .product(name: "FoundationExtension", package: "FoundationExtension"),
                         .product(name: "Logging", package: "swift-log"),
                         .product(name: "ShellKit", package: "FoundationExtension"),
                     ]),
        .testTarget(name: "DependencyCollectorTests",
                     dependencies: [
                         "DependencyCollector",
                         "SharedStructs",
                         .product(name: "FoundationExtension", package: "FoundationExtension"),
                         .product(name: "Logging", package: "swift-log"),
                     ]),
        .testTarget(name: "DependencyGraphTests",
                     dependencies: [
                         "DependencyGraph",
                     ]),
        .testTarget(name: "EnvironmentSetupTests",
                     dependencies: [
                         "EnvironmentSetup",
                         "SharedStructs",
                         .product(name: "FoundationExtension", package: "FoundationExtension"),
                         .product(name: "Logging", package: "swift-log"),
                     ]),
        .testTarget(name: "SwiftAndroidBuilderTests",
                     dependencies: [
                         "SharedStructs",
                         "SwiftAndroidBuilder",
                         .product(name: "FoundationExtension", package: "FoundationExtension"),
                     ]),
        .testTarget(name: "SwiftAndroidBuilderIntegrationTests",
                     dependencies: [
                         "DependencyGraph",
                         "SharedStructs",
                         "SwiftAndroidBuilder",
                         .product(name: "FoundationExtension", package: "FoundationExtension"),
                         .product(name: "Logging", package: "swift-log"),
                     ]),
    ]
)
