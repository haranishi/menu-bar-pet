// swift-tools-version: 6.1
import PackageDescription
import Foundation

let rustLibrary = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("rust/target/release").path

let package = Package(
    name: "MenuBarPet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MenuBarPet", targets: ["MenuBarPet"]),
        .executable(name: "MenuBarPetTests", targets: ["MenuBarPetTests"]),
        .library(name: "MenuBarPetCore", targets: ["MenuBarPetCore"]),
    ],
    targets: [
        .systemLibrary(name: "CMbpCore"),
        .target(
            name: "MenuBarPetCore",
            dependencies: ["CMbpCore"],
            linkerSettings: [
                .unsafeFlags(["-L", rustLibrary]),
                .linkedLibrary("menubar_pet_core"),
            ]
        ),
        .executableTarget(
            name: "MenuBarPet",
            dependencies: ["MenuBarPetCore"]
        ),
        .executableTarget(
            name: "MenuBarPetTests",
            dependencies: ["MenuBarPetCore"],
            path: "Tests/MenuBarPetCoreTests"
        ),
    ]
)
