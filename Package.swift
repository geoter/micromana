// swift-tools-version: 5.9
// The macOS app is built with Xcode (Micromana.xcodeproj).
// This manifest exists so `swift package` commands can resolve the repo without errors.
import PackageDescription

let package = Package(
    name: "Micromana",
    platforms: [.macOS(.v13)],
    products: [],
    targets: [
        .target(name: "MicromanaPlaceholder", path: "Sources/Placeholder")
    ]
)
