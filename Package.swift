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
        // No `resources:` here on purpose. The directory only ever held a
        // .gitkeep, and declaring it made SwiftPM emit an empty
        // FavWidgets_FavWidgets.bundle that Xcode 17 refuses to codesign
        // ("bundle format unrecognized"), failing the whole app build.
        // Add it back only alongside a real asset.
        .target(name: "FavWidgets", dependencies: ["FavWidgetsCore"]),
        .testTarget(name: "FavWidgetsCoreTests", dependencies: ["FavWidgetsCore"]),
        .testTarget(name: "FavWidgetsTests", dependencies: ["FavWidgets"])
    ],
    swiftLanguageModes: [.v5]
)
