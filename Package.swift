// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SimpleCmux",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "simple", targets: ["SimpleCmux"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.15.0")
    ],
    targets: [
        .executableTarget(
            name: "SimpleCmux",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ]
        )
    ]
)
