// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CRDTKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "CRDTKit", targets: ["CRDTKit"]),
        .library(name: "CRDTTransport", targets: ["CRDTTransport"]),
    ],
    targets: [
        .target(name: "CRDTKit"),
        .target(name: "CRDTTransport", dependencies: ["CRDTKit"]),
        .testTarget(name: "CRDTKitTests", dependencies: ["CRDTKit"]),
        .testTarget(name: "CRDTTransportTests", dependencies: ["CRDTTransport"]),
    ]
)
