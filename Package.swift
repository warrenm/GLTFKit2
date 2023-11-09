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
                      url: "https://github.com/warrenm/GLTFKit2/releases/download/0.5.3/GLTFKit2.xcframework.zip",
                      checksum: "eefcd219d57d77bc7b3232401b47ef89160e8b9a58afbc456cde84a306c0ec6f")
    ]
)
