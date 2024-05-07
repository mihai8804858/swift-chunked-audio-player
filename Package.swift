// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "swift-chunked-audio-player",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
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
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")]
        )
    ]
)
