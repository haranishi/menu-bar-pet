// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MenuBarPet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MenuBarPet", targets: ["MenuBarPet"]),
    ],
    targets: [
        .executableTarget(name: "MenuBarPet"),
    ]
)
