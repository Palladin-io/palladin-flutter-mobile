// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "EntrySharingCore",
  platforms: [.macOS(.v12), .iOS(.v14)],
  products: [.library(name: "EntrySharingCore", targets: ["EntrySharingCore"])],
  targets: [
    .target(name: "EntrySharingCore"),
    .testTarget(name: "EntrySharingCoreTests", dependencies: ["EntrySharingCore"]),
  ]
)
