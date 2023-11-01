// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "GLTFKit2",
    platforms: [
        .macOS("11.0"), .iOS("12.1")
    ],
    products: [
        .library(name: "GLTFKit2",
                 targets: [ "GLTFKit2" ])
    ],
    targets: [
        .binaryTarget(name: "GLTFKit2",
                      url: "https://github.com/warrenm/GLTFKit2/releases/download/0.5.2/GLTFKit2.xcframework.zip",
                      checksum: "46d7e3c8ab7d79bf4fd37fd5695b260a0d47ca2c202a562d13310329ad5a2014")
    ]
)
