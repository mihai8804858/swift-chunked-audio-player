// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "swift-chunked-audio-player",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "ChunkedAudioPlayer",
            targets: ["ChunkedAudioPlayer"]
        )
    ],
    targets: [
        .target(
            name: "ChunkedAudioPlayer",
            path: "Sources",
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ],
    swiftLanguageModes: [.v6]
)
