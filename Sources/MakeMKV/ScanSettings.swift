// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import Foundation

/// The switches that change what a scan sees, and therefore what a title index means.
///
/// A rip reuses the settings of the scan it came from, without exception, because MakeMKV numbers
/// titles positionally after applying the minimum length and its duplicate-playlist rule: change
/// either and title 3 is a different title. The switch names are the ones `makemkvcon` itself
/// recognises, checked against the binary rather than the documentation.
public struct ScanSettings: Hashable, Sendable {
    /// `--minlength=SECONDS`. Titles shorter than this are not listed. MakeMKV's own default is 120.
    public var minimumTitleLength: Int?
    /// `--cache=MEGABYTES`, the read cache.
    public var cacheMegabytes: Int?
    /// `--directio=true|false`, bypassing the operating system's disc cache.
    public var directIO: Bool?
    /// `--profile=PATH`, a conversion profile. This is the per-run way to set the track selection
    /// rule, and so the way to make a rip's stream layout deterministic rather than whatever the
    /// installed preferences say.
    public var profile: URL?
    /// `--noscan`: do not touch drives on startup. Useful with `.iso` and `.folder` sources.
    public var noScan = false
    /// Anything else, passed through verbatim before the command.
    public var additionalArguments: [String] = []

    public init(
        minimumTitleLength: Int? = nil,
        cacheMegabytes: Int? = nil,
        directIO: Bool? = nil,
        profile: URL? = nil,
        noScan: Bool = false,
        additionalArguments: [String] = []
    ) {
        self.minimumTitleLength = minimumTitleLength
        self.cacheMegabytes = cacheMegabytes
        self.directIO = directIO
        self.profile = profile
        self.noScan = noScan
        self.additionalArguments = additionalArguments
    }

    /// The switches, in a fixed order, without `-r` and the output switches the driver adds.
    public var arguments: [String] {
        var arguments: [String] = []
        if let minimumTitleLength {
            arguments.append("--minlength=\(minimumTitleLength)")
        }
        if let cacheMegabytes {
            arguments.append("--cache=\(cacheMegabytes)")
        }
        if let directIO {
            arguments.append("--directio=\(directIO)")
        }
        if let profile {
            arguments.append("--profile=\(profile.path)")
        }
        if noScan {
            arguments.append("--noscan")
        }
        arguments.append(contentsOf: additionalArguments)
        return arguments
    }
}
