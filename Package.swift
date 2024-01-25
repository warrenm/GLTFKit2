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
                      url: "https://github.com/warrenm/GLTFKit2/releases/download/0.5.8/GLTFKit2.xcframework.zip",
                      checksum:"e9d375706bc91ffa0fa75ae68c6759068e2b70e7ca22b75caf4a91fda4a1b018")
    ]
)
