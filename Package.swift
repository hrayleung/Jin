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
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.11.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.16.0"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "8.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.4.0")
    ],
    targets: [
        .executableTarget(
            name: "Jin",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "TTSKit", package: "WhisperKit"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "Collections", package: "swift-collections")
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
