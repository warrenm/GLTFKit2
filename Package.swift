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
                      url: "https://github.com/warrenm/GLTFKit2/releases/download/0.5.11/GLTFKit2.xcframework.zip",
                      checksum:"a3d62ba63ae946553acb0e3fb60b7183966841cd2c492ceb47fc6d5df227dab8")
    ]
)
