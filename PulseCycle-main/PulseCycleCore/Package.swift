// swift-tools-version:5.9

// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import PackageDescription

let package = Package(
    name: "PulseCycleCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "PulseCycleCore", targets: ["PulseCycleCore"]),
    ],
    targets: [
        .target(name: "PulseCycleCore"),
    ]
)
