// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CRDTKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "CRDTKit", targets: ["CRDTKit"]),
    ],
    targets: [
        .target(name: "CRDTKit"),
        .testTarget(name: "CRDTKitTests", dependencies: ["CRDTKit"]),
    ]
)
