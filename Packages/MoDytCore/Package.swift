// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MoDytCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MoDytCore", targets: ["MoDytCore"])
    ],
    targets: [
        .target(name: "MoDytCore")
    ]
)
