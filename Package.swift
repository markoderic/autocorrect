// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoCorrect",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AutoCorrect", targets: ["AutoCorrect"]),
               .library(name: "AutoCorrectCore", targets: ["AutoCorrectCore"])],
    targets: [
        .target(name: "AutoCorrectCore"),
        .executableTarget(name: "AutoCorrect", dependencies: ["AutoCorrectCore"]),
        .testTarget(name: "AutoCorrectCoreTests", dependencies: ["AutoCorrectCore"]),
        .testTarget(name: "AutoCorrectTests", dependencies: ["AutoCorrect", "AutoCorrectCore"])
    ]
)
