// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import PackageDescription

let package = Package(
    name: "MakeMKVKit",
    platforms: [.macOS(.v14)],
    products: [
        // The wire format alone: parse robot-mode output that came from anywhere — a live process, a
        // saved log, TheDiscDb's data repository — with no dependency on a MakeMKV installation.
        .library(name: "MakeMKVRobot", targets: ["MakeMKVRobot"]),
        // The driver: locate makemkvcon, scan a disc, rip a title from that scan.
        .library(name: "MakeMKV", targets: ["MakeMKV"]),
    ],
    targets: [
        .target(name: "MakeMKVRobot"),
        .target(name: "MakeMKV", dependencies: ["MakeMKVRobot"]),
        .testTarget(
            name: "MakeMKVRobotTests",
            dependencies: ["MakeMKVRobot"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "MakeMKVTests", dependencies: ["MakeMKV"]),
    ]
)
