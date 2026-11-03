// swift-tools-version:5.9

// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import PackageDescription

let package = Package(
    name: "PulseCycle",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PulseCycleMacGUI", targets: ["PulseCycleMacGUI"]),
    ],
    dependencies: [
        .package(path: "PulseCycleCore"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "PulseCycleMacGUI",
            dependencies: [
                .product(name: "PulseCycleCore", package: "PulseCycleCore"),
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
    ]
)
