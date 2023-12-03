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
                      url: "https://github.com/warrenm/GLTFKit2/releases/download/0.5.4/GLTFKit2.xcframework.zip",
                      checksum: "db39145e7d58f1d617e995f5566c8bef2f44b785299d7a3259d6fa5a66e083d8")
    ]
)
