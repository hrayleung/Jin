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
        .package(url: "https://github.com/LiYanan2004/MarkdownView", from: "2.5.2")
    ],
    targets: [
        .executableTarget(
            name: "Jin",
            dependencies: [
                .product(name: "MarkdownView", package: "MarkdownView")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "JinTests",
            dependencies: ["Jin"],
            path: "Tests/JinTests"
        )
    ]
)
