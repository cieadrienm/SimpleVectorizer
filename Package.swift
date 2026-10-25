// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimpleVectorizer",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SimpleVectorizerCore", targets: ["SimpleVectorizerCore"]),
        .library(name: "SimpleVectorizerMCPCore", targets: ["SimpleVectorizerMCPCore"]),
        .executable(name: "SimpleVectorizer", targets: ["SimpleVectorizer"]),
        .executable(name: "simplevectorizer-mcp", targets: ["simplevectorizer-mcp"]),
    ],
    targets: [
        .target(name: "SimpleVectorizerCore"),
        .executableTarget(name: "SimpleVectorizer", dependencies: ["SimpleVectorizerCore"]),
        .target(name: "SimpleVectorizerMCPCore"),
        .executableTarget(name: "simplevectorizer-mcp", dependencies: ["SimpleVectorizerMCPCore"]),
        .testTarget(name: "SimpleVectorizerCoreTests", dependencies: ["SimpleVectorizerCore"]),
        .testTarget(name: "SimpleVectorizerAppTests", dependencies: ["SimpleVectorizer", "SimpleVectorizerCore", "SimpleVectorizerMCPCore"]),
    ],
    swiftLanguageModes: [.v5]
)
