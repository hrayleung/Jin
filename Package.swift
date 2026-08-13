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
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.11.0"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "8.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.4.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.6.0"),
        .package(url: "https://github.com/smittytone/HighlighterSwift.git", from: "3.0.3"),
        // Vendored, locally-patched fork of mgriebling/SwiftMath (MIT) for native
        // Core Text math rendering — see Sources/UI/NativeMarkdown/MathRenderer.swift.
        .package(path: "Vendor/SwiftMath")
    ],
    targets: [
        .executableTarget(
            name: "Jin",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Highlighter", package: "HighlighterSwift"),
                .product(name: "SwiftMath", package: "SwiftMath")
            ],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "JinTests",
            dependencies: ["Jin", .product(name: "SwiftMath", package: "SwiftMath")],
            path: "Tests/JinTests"
        )
    ]
)
