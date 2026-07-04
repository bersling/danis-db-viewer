// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DanisDBViewer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/vapor/mysql-nio.git", from: "1.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "DanisDBViewer",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "MySQLNIO", package: "mysql-nio"),
            ],
            path: "Sources/DanisDBViewer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DanisDBViewerTests",
            dependencies: ["DanisDBViewer"],
            path: "Tests/DanisDBViewerTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
