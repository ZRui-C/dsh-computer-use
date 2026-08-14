// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DSHComputerUse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "DSHComputerUse",
            targets: ["DSHComputerUse"]
        )
    ],
    targets: [
        .target(
            name: "DSHComputerUseCore",
            path: "Sources/DSHComputerUseCore"
        ),
        .executableTarget(
            name: "DSHComputerUse",
            dependencies: ["DSHComputerUseCore"],
            path: "Sources/DSHComputerUse"
        ),
        .testTarget(
            name: "DSHComputerUseCoreTests",
            dependencies: ["DSHComputerUseCore"],
            path: "Tests/DSHComputerUseCoreTests"
        ),
    ]
)
