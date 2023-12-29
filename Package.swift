// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "FastRTPSBridge",
    products: [
        .library(
            name: "FastRTPSBridge",
            type: .dynamic,
            targets: ["FastRTPSBridge"]),
    ],
    dependencies: [
        .package(name: "CDRCodable", url: "https://github.com/DimaRU/CDRCodable.git", from: "1.0.0"),
        .package(name: "FastDDS", url: "https://github.com/huyaoyu/FastDDSPrebuild.git", .upToNextMajor(from: "2.6.6"))
    ],
    targets: [
        .target(
            name: "FastRTPSWrapper",
            dependencies: ["FastDDS"],
            path: "Sources/FastRTPSWrapper"),
        .target(
            name: "FastRTPSBridge",
            dependencies: ["CDRCodable", "FastRTPSWrapper"],
            path: "Sources/FastRTPSBridge"),
        .testTarget(
            name: "FastRTPSBridgeTests",
            dependencies: ["FastRTPSBridge"]),
    ],
    //swiftLanguageVersions: [.v5],
    cxxLanguageStandard: .cxx11
)

#if os(Linux)
package.dependencies.removeAll(where: { $0.name == "FastDDS"})
package.targets.first(where: { $0.name == "FastRTPSWrapper"})!.dependencies = []
package.targets.first(where: { $0.name == "FastRTPSBridge"})!.linkerSettings = [
    .linkedLibrary("fastrtps", .when(platforms: [.linux])),
    .unsafeFlags(["-L/usr/local/lib"], .when(platforms: [.linux]))
]
#endif
