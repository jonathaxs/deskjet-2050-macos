// swift-tools-version: 6.0
// The DeskJet 2050 app: shows the ink levels and helps install the driver.
// Build the .app with scripts/build-app.sh; `swift build` alone only makes the executable.
import PackageDescription

let package = Package(
    name: "DeskJet2050",
    platforms: [.macOS(.v14)],
    targets: [
        // USB reading shared with the CUPS filter. The files are links to driver/files/src.
        .target(
            name: "LEDM",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(
            name: "DeskJet2050",
            dependencies: ["LEDM"]
        ),
    ]
)
