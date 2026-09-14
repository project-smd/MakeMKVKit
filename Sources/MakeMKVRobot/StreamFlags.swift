// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

/// The `StreamFlags` attribute of a track, bit for bit the `AP_AVStreamFlag_*` constants in
/// `apdefs.h` from makemkv-oss.
///
/// Two of these carry structure rather than description. `hasCoreAudio` marks a lossless track
/// that embeds a lossy core, and the track listed immediately after it carries `derivedStream`
/// and `coreAudio`: that is the core, presented as a track of its own, which the MakeMKV GUI nests
/// under its parent. `derivedStream` with `forcedSubtitles` is the same idea for subtitles, a
/// forced-only stream MakeMKV extracts from the full one.
public struct StreamFlags: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let directorsComments = StreamFlags(rawValue: 1)
    public static let alternateDirectorsComments = StreamFlags(rawValue: 2)
    public static let forVisuallyImpaired = StreamFlags(rawValue: 4)
    public static let coreAudio = StreamFlags(rawValue: 256)
    public static let secondaryAudio = StreamFlags(rawValue: 512)
    public static let hasCoreAudio = StreamFlags(rawValue: 1024)
    public static let derivedStream = StreamFlags(rawValue: 2048)
    public static let forcedSubtitles = StreamFlags(rawValue: 4096)
    public static let profileSecondaryStream = StreamFlags(rawValue: 16384)
    public static let offsetSequenceIdPresent = StreamFlags(rawValue: 32768)
}
