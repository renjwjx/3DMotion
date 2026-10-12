// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Body3DMac",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(name: "Body3DMac", targets: ["Body3DMac"])
    ],
    targets: [
        .executableTarget(
            name: "Body3DMac",
            path: "Sources/Body3DMac"
        )
    ]
)
