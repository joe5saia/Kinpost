// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KinpostKit",
    platforms: [.iOS("27.0"), .macOS(.v14)],
    products: [.library(name: "KinpostCore", targets: ["KinpostCore"]),
               .executable(name: "kinpost", targets: ["KinpostCLI"])],
    targets: [.target(name: "KinpostCore"),
              .executableTarget(name: "KinpostCLI", dependencies: ["KinpostCore"])])
