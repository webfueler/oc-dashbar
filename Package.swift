// swift-tools-version: 6.0
import PackageDescription

// Deployment target: macOS 26 (Tahoe), raised from 15 when the popover moved
// to NSGlassEffectView, which is macOS 26 and nothing older. One floor buys
// one code path: the class is referenced unguarded in PanelMaterial.swift, so
// a silent fallback to the older NSVisualEffectView is not representable. If
// the floor goes back to 15, that reference stops compiling and the guard has
// to be an `if #available` that chooses a material the log cannot promise by
// name.
// The cost, named: a macOS 15 machine refuses to launch this app. macOS 26 is
// the newer of the two systems Apple still ships security updates for, so the
// floor is not shorter lived than the one it replaced.
let package = Package(
    name: "OCDashBar",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "oc-dashbar", targets: ["oc-dashbar"])
    ],
    targets: [
        .executableTarget(
            name: "oc-dashbar",
            path: "Sources/oc-dashbar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "oc-dashbar-tests",
            dependencies: ["oc-dashbar"],
            path: "Tests/oc-dashbar-tests"
        ),
    ]
)
