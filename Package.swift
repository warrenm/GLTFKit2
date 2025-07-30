//swift-tools-version: 5.5

import PackageDescription

let package = Package(
    name: "GLTFKit2",
    platforms: [
        .macOS("11.0"), .macCatalyst("14.0"), .iOS("12.1"), .tvOS("12.1")
        // Note: visionOS("1.0") is also supported, but we can't require Swift tools version 5.9 yet.
    ],
    products: [
        .library(name: "GLTFKit2",
                 targets: [ "GLTFKit2" ])
    ],
    targets: [
        .binaryTarget(name: "GLTFKit2",
                      url: "https://github.com/warrenm/GLTFKit2/releases/download/0.5.14/GLTFKit2.xcframework.zip",
                      checksum:"770959997097fa1f78d1ba2c77ac87f41dbcd61f05e4eb498fe7dfc063a900a6")
    ]
)
