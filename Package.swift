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
                      url: "https://github.com/warrenm/GLTFKit2/releases/download/0.5.5/GLTFKit2.xcframework.zip",
                      checksum: "bd91c172d9d9395a550395e6729a139524d2d3e8823c069b836e681ce93b2a5a")
    ]
)
