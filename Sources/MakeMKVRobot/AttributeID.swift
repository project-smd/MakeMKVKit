// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

/// The numeric id in the second field of a `CINFO`, `TINFO` or `SINFO` line.
///
/// Names mirror `AP_ItemAttributeId` in `apdefs.h` from the makemkv-oss sources, with the `ap_ia`
/// prefix dropped and nothing else renamed, so any field here can be grepped against upstream. A
/// struct rather than an enum so that an id this version has never heard of survives parsing and
/// round-trips; `name` is `nil` for those.
public struct AttributeID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let unknown = AttributeID(rawValue: 0)
    public static let type = AttributeID(rawValue: 1)
    public static let name = AttributeID(rawValue: 2)
    public static let langCode = AttributeID(rawValue: 3)
    public static let langName = AttributeID(rawValue: 4)
    public static let codecId = AttributeID(rawValue: 5)
    public static let codecShort = AttributeID(rawValue: 6)
    public static let codecLong = AttributeID(rawValue: 7)
    public static let chapterCount = AttributeID(rawValue: 8)
    public static let duration = AttributeID(rawValue: 9)
    public static let diskSize = AttributeID(rawValue: 10)
    public static let diskSizeBytes = AttributeID(rawValue: 11)
    public static let streamTypeExtension = AttributeID(rawValue: 12)
    public static let bitrate = AttributeID(rawValue: 13)
    public static let audioChannelsCount = AttributeID(rawValue: 14)
    public static let angleInfo = AttributeID(rawValue: 15)
    public static let sourceFileName = AttributeID(rawValue: 16)
    public static let audioSampleRate = AttributeID(rawValue: 17)
    public static let audioSampleSize = AttributeID(rawValue: 18)
    public static let videoSize = AttributeID(rawValue: 19)
    public static let videoAspectRatio = AttributeID(rawValue: 20)
    public static let videoFrameRate = AttributeID(rawValue: 21)
    public static let streamFlags = AttributeID(rawValue: 22)
    public static let dateTime = AttributeID(rawValue: 23)
    public static let originalTitleId = AttributeID(rawValue: 24)
    public static let segmentsCount = AttributeID(rawValue: 25)
    public static let segmentsMap = AttributeID(rawValue: 26)
    public static let outputFileName = AttributeID(rawValue: 27)
    public static let metadataLanguageCode = AttributeID(rawValue: 28)
    public static let metadataLanguageName = AttributeID(rawValue: 29)
    public static let treeInfo = AttributeID(rawValue: 30)
    public static let panelTitle = AttributeID(rawValue: 31)
    public static let volumeName = AttributeID(rawValue: 32)
    public static let orderWeight = AttributeID(rawValue: 33)
    public static let outputFormat = AttributeID(rawValue: 34)
    public static let outputFormatDescription = AttributeID(rawValue: 35)
    public static let seamlessInfo = AttributeID(rawValue: 36)
    public static let panelText = AttributeID(rawValue: 37)
    public static let mkvFlags = AttributeID(rawValue: 38)
    public static let mkvFlagsText = AttributeID(rawValue: 39)
    public static let audioChannelLayoutName = AttributeID(rawValue: 40)
    public static let outputCodecShort = AttributeID(rawValue: 41)
    public static let outputConversionType = AttributeID(rawValue: 42)
    public static let outputAudioSampleRate = AttributeID(rawValue: 43)
    public static let outputAudioSampleSize = AttributeID(rawValue: 44)
    public static let outputAudioChannelsCount = AttributeID(rawValue: 45)
    public static let outputAudioChannelLayoutName = AttributeID(rawValue: 46)
    public static let outputAudioChannelLayout = AttributeID(rawValue: 47)
    public static let outputAudioMixDescription = AttributeID(rawValue: 48)
    public static let comment = AttributeID(rawValue: 49)
    public static let offsetSequenceId = AttributeID(rawValue: 50)

    /// The upstream name without its `ap_ia` prefix, or `nil` for an id not in the header this
    /// package was written against.
    public var name: String? {
        Self.names[rawValue]
    }

    public var description: String {
        name.map { "\($0)(\(rawValue))" } ?? "attribute(\(rawValue))"
    }

    private static let names: [Int: String] = [
        0: "Unknown", 1: "Type", 2: "Name", 3: "LangCode", 4: "LangName", 5: "CodecId",
        6: "CodecShort", 7: "CodecLong", 8: "ChapterCount", 9: "Duration", 10: "DiskSize",
        11: "DiskSizeBytes", 12: "StreamTypeExtension", 13: "Bitrate", 14: "AudioChannelsCount",
        15: "AngleInfo", 16: "SourceFileName", 17: "AudioSampleRate", 18: "AudioSampleSize",
        19: "VideoSize", 20: "VideoAspectRatio", 21: "VideoFrameRate", 22: "StreamFlags",
        23: "DateTime", 24: "OriginalTitleId", 25: "SegmentsCount", 26: "SegmentsMap",
        27: "OutputFileName", 28: "MetadataLanguageCode", 29: "MetadataLanguageName",
        30: "TreeInfo", 31: "PanelTitle", 32: "VolumeName", 33: "OrderWeight", 34: "OutputFormat",
        35: "OutputFormatDescription", 36: "SeamlessInfo", 37: "PanelText", 38: "MkvFlags",
        39: "MkvFlagsText", 40: "AudioChannelLayoutName", 41: "OutputCodecShort",
        42: "OutputConversionType", 43: "OutputAudioSampleRate", 44: "OutputAudioSampleSize",
        45: "OutputAudioChannelsCount", 46: "OutputAudioChannelLayoutName",
        47: "OutputAudioChannelLayout", 48: "OutputAudioMixDescription", 49: "Comment",
        50: "OffsetSequenceId",
    ]
}
