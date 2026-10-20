// swift-tools-version: 6.0
import PackageDescription

// FavWidgets — the FavCircles "Widgets" home-tab mini-apps.
//
// Two modules on purpose: `FavWidgetsCore` is Foundation-only (contract,
// models, sync, pure logic) so `swift test` runs on a Mac without a
// simulator; `FavWidgets` is the SwiftUI layer the app hosts. The app links
// the single `FavWidgets` product and gets both.
let package = Package(
    name: "FavWidgets",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "FavWidgets", targets: ["FavWidgets", "FavWidgetsCore"])
    ],
    targets: [
        .target(name: "FavWidgetsCore"),
        // Resources: the Sleep Sounds recordings (2026-10-19). Keep the
        // folder non-empty: an empty FavWidgets_FavWidgets.bundle is one
        // Xcode 17 refuses to codesign ("bundle format unrecognized").
        .target(name: "FavWidgets", dependencies: ["FavWidgetsCore"], resources: [.process("Resources")]),
        .testTarget(name: "FavWidgetsCoreTests", dependencies: ["FavWidgetsCore"]),
        .testTarget(name: "FavWidgetsTests", dependencies: ["FavWidgets"])
    ],
    swiftLanguageModes: [.v5]
)
