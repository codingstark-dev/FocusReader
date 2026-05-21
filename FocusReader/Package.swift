// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FocusReader",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FocusReader", targets: ["FocusReader"]),
    ],
    targets: [
        .executableTarget(
            name: "FocusReader",
            path: "Sources/FocusReader"
        ),
    ]
)
