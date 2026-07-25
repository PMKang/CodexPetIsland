// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexPetIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexPetIsland", targets: ["CodexPetIsland"])
    ],
    targets: [
        .executableTarget(name: "CodexPetIsland"),
        .testTarget(
            name: "CodexPetIslandTests",
            dependencies: ["CodexPetIsland"]
        )
    ]
)
