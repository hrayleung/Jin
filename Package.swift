// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Jin",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Jin",
            targets: ["Jin"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Jin",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "JinTests",
            dependencies: ["Jin"],
            path: "Tests/JinTests"
        )
    ]
)
