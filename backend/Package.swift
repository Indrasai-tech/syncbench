// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SyncBenchServer",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "syncbench-server", targets: ["SyncBenchServer"])],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .executableTarget(name: "SyncBenchServer", dependencies: [.product(name: "Vapor", package: "vapor"), .product(name: "Crypto", package: "swift-crypto")]),
        .testTarget(name: "SyncBenchServerTests", dependencies: ["SyncBenchServer"])
    ]
)
