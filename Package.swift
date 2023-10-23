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
                      url: "https://github.com/warrenm/GLTFKit2/releases/download/0.5.0/GLTFKit2.xcframework.zip",
                      checksum: "4c73fa160c2cd8e2a5e1addb5d92eca9e8f296edeb49549fbf2036c10e27b012")
    ]
)
