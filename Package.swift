// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "DynamicGeometry",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(
      name: "DynamicGeometry",
      targets: ["DynamicGeometry"]
    )
  ],
  targets: [
    .target(name: "DynamicGeometry"),
    .testTarget(
      name: "DynamicGeometryTests",
      dependencies: ["DynamicGeometry"]
    ),
  ]
)
