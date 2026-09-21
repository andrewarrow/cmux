// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SimpleCmux",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "simple", targets: ["SimpleCmux"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SimpleCmux",
            dependencies: ["GhosttyKit"],
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        ),
        // cmux and Ghostty use the same embedded libghostty surface model.
        // The archive is provisioned locally by scripts/ensure-ghosttykit.sh
        // so the repository does not carry a 500 MB renderer checkout.
        .binaryTarget(
            name: "GhosttyKit",
            path: "Vendor/GhosttyKit.xcframework"
        )
    ]
)
