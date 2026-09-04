// swift-tools-version: 6.0
import PackageDescription

// MidnightKit — on-device zero-knowledge proving for Midnight, on iOS.
//
// The Rust prover (slip-prove-ffi) lives outside this repo, on the external volume
// with the rest of the spike, and is NOT vendored here: the archive is ~60 MB per
// architecture and is reproducible from source. `scripts/sync-prover.sh` copies the
// built archive into Vendor/ before a build.
//
// One Rust staticlib, deliberately: two libraries that each pull midnight-curves
// both embed blst and collide on duplicate symbols under -force_load. Everything
// the app needs (prove, verify, keys) exposes from this single archive.
let package = Package(
    name: "MidnightKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MidnightKit", targets: ["MidnightKit"])
    ],
    targets: [
        // C shim over the Rust C-ABI.
        .target(
            name: "CSlipProve",
            path: "Sources/CSlipProve",
            linkerSettings: [
                .unsafeFlags(["-LVendor", "-lslip_prove_ffi"]),
                .linkedFramework("Security"),
                .linkedLibrary("c++")
            ]
        ),
        .target(
            name: "MidnightKit",
            dependencies: ["CSlipProve"],
            path: "Sources/MidnightKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MidnightKitTests",
            dependencies: ["MidnightKit"],
            path: "Tests/MidnightKitTests"
        )
    ]
)
