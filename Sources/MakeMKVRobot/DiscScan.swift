// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

/// Everything one `makemkvcon info` run said, sorted into the shape it describes.
///
/// `lines` keeps the whole log in order, so nothing is lost by building this; the other properties
/// are that log read for its facts. `disc` is `nil` when the run never reached a disc — no drive,
/// no medium, or a failure before the title list — and `messages` says why.
public struct DiscScan: Hashable, Sendable {
    public var lines: [RobotLine]
    public var drives: [Drive]
    public var messages: [Message]
    public var disc: DiscInfo?
    /// Lines this package could not read, verbatim. `HSH:` lines from TheDiscDb land here.
    public var unrecognised: [String]

    public init(lines: [RobotLine]) {
        self.lines = lines
        var drives: [Drive] = []
        var messages: [Message] = []
        var unrecognised: [String] = []
        var titleCount: Int?
        var discAttributes: [AttributeID: Attribute] = [:]
        var titles: [Int: (attributes: [AttributeID: Attribute], tracks: [Int: [AttributeID: Attribute]])] = [:]

        for line in lines {
            switch line {
            case .message(let message):
                messages.append(message)
            case .drive(let drive):
                drives.append(drive)
            case .titleCount(let count):
                titleCount = count
            case .discAttribute(let attribute):
                discAttributes[attribute.id] = attribute
            case .titleAttribute(let title, let attribute):
                titles[title, default: ([:], [:])].attributes[attribute.id] = attribute
            case .streamAttribute(let title, let stream, let attribute):
                titles[title, default: ([:], [:])].tracks[stream, default: [:]][attribute.id] = attribute
            case .unrecognised(let text):
                unrecognised.append(text)
            case .progressCurrent, .progressTotal, .progressValue:
                break
            }
        }

        self.drives = drives
        self.messages = messages
        self.unrecognised = unrecognised

        if titleCount != nil || !discAttributes.isEmpty || !titles.isEmpty {
            let built = titles.keys.sorted().map { index -> Title in
                let entry = titles[index]!
                let tracks = entry.tracks.keys.sorted().map { Track(index: $0, attributes: entry.tracks[$0]!) }
                return Title(index: index, attributes: entry.attributes, tracks: tracks)
            }
            disc = DiscInfo(titleCount: titleCount ?? built.count, attributes: discAttributes, titles: built)
        } else {
            disc = nil
        }
    }

    public init(parsing text: String) {
        self.init(lines: RobotLineParser.parse(text))
    }

    /// The first message with the given code, if any.
    public func message(code: Int) -> Message? {
        messages.first { $0.code == code }
    }
}

/// Shared by the disc, a title and a stream: a bag of attributes with typed reads over it.
///
/// The bags are `Codable`, so a title can be kept after the scan it came from is gone — a tool
/// that queues ripped files for later work needs the title as it was, tracks and all, and a title
/// index alone means nothing without its scan. Keys encode as their raw ids.
public protocol AttributeBearing {
    var attributes: [AttributeID: Attribute] { get }
}

extension AttributeBearing {
    public subscript(id: AttributeID) -> String? {
        attributes[id]?.value
    }

    public func integer(_ id: AttributeID) -> Int? {
        attributes[id].flatMap { Int($0.value) }
    }
}

public struct DiscInfo: AttributeBearing, Hashable, Sendable, Codable {
    /// From `TCOUNT`, which MakeMKV prints before the titles; falls back to the titles seen.
    public var titleCount: Int
    public var attributes: [AttributeID: Attribute]
    public var titles: [Title]

    public init(titleCount: Int, attributes: [AttributeID: Attribute], titles: [Title]) {
        self.titleCount = titleCount
        self.attributes = attributes
        self.titles = titles
    }

    public var name: String? { self[.name] }
    public var volumeName: String? { self[.volumeName] }
    public var metadataLanguageCode: String? { self[.metadataLanguageCode] }

    /// Read from the message code on the `Type` attribute, not its text, which is localised.
    public var mediaType: MediaType {
        switch attributes[.type]?.messageCode {
        case 6206: .dvd
        case 6209: .bluray
        case let code?: .other(code: code)
        case nil: .other(code: 0)
        }
    }

    public func title(index: Int) -> Title? {
        titles.first { $0.index == index }
    }
}

/// What kind of disc MakeMKV opened. UHD discs report the same code as Blu-ray.
public enum MediaType: Hashable, Sendable, Codable {
    case dvd
    case bluray
    case other(code: Int)
}

public struct Title: AttributeBearing, Hashable, Sendable, Codable {
    /// MakeMKV's title index — the number `mkv` takes. It is positional and depends on the scan
    /// settings, so it means something only against the scan that produced it.
    public var index: Int
    public var attributes: [AttributeID: Attribute]
    public var tracks: [Track]

    public init(index: Int, attributes: [AttributeID: Attribute], tracks: [Track]) {
        self.index = index
        self.attributes = attributes
        self.tracks = tracks
    }

    public var name: String? { self[.name] }
    public var chapterCount: Int? { integer(.chapterCount) }
    /// `h:mm:ss` as printed.
    public var durationText: String? { self[.duration] }
    public var durationSeconds: Int? { durationText.flatMap(Title.seconds(from:)) }
    public var duration: Duration? { durationSeconds.map { .seconds($0) } }
    public var diskSizeText: String? { self[.diskSize] }
    public var sizeBytes: Int? { integer(.diskSizeBytes) }
    /// The playlist or clip on a Blu-ray — `00117.mpls`, `00005.m2ts`. Absent on DVD.
    public var sourceFileName: String? { self[.sourceFileName] }
    /// The VTS title number on a DVD — `03`. Absent on Blu-ray.
    public var originalTitleId: String? { self[.originalTitleId] }
    /// Whichever of the two the disc has. This is what TheDiscDb records as `SourceFile`, and
    /// with `segmentMap` and `durationText` it is the stable identity of a title across scans.
    public var sourceIdentifier: String? { sourceFileName ?? originalTitleId }
    public var segmentCount: Int? { integer(.segmentsCount) }
    /// `45`, `151,5`, `1-6`: the clips or cells the title plays, in MakeMKV's notation.
    public var segmentMap: String? { self[.segmentsMap] }
    /// The file `mkv` will write into the destination folder.
    public var outputFileName: String? { self[.outputFileName] }
    public var angleInfo: String? { self[.angleInfo] }
    public var treeInfo: String? { self[.treeInfo] }
    public var orderWeight: Int? { integer(.orderWeight) }
    public var comment: String? { self[.comment] }

    public var videoTracks: [Track] { tracks.filter { $0.kind == .video } }
    public var audioTracks: [Track] { tracks.filter { $0.kind == .audio } }
    public var subtitleTracks: [Track] { tracks.filter { $0.kind == .subtitles } }

    /// The tracks that are things in their own right: everything not derived from another.
    public var primaryTracks: [Track] { tracks.filter { !$0.isDerived } }

    /// The tracks MakeMKV derived from `parent` — its lossy core, a forced-only subtitle stream —
    /// which are the derived tracks that follow it, up to the next primary one. MakeMKV lists a
    /// derived stream directly after the stream it came from; that adjacency is the only link.
    public func derivedTracks(of parent: Track) -> [Track] {
        guard let start = tracks.firstIndex(of: parent) else { return [] }
        return Array(tracks[tracks.index(after: start)...].prefix { $0.isDerived })
    }

    /// The primary track a derived one came from, or `nil` for a primary track.
    public func parentTrack(of track: Track) -> Track? {
        guard track.isDerived, let position = tracks.firstIndex(of: track) else { return nil }
        return tracks[..<position].last { !$0.isDerived }
    }

    static func seconds(from text: String) -> Int? {
        let parts = text.split(separator: ":").map { Int($0) }
        guard parts.allSatisfy({ $0 != nil }), (1...3).contains(parts.count) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }
}

/// One stream of a title — an `SINFO` row. Named as the GUI names them, "track", partly because
/// that is the word on its info panel and partly because Foundation already owns `Stream`.
public struct Track: AttributeBearing, Hashable, Sendable, Codable {
    /// MakeMKV's stream index within the title, as the disc has it. A ripped file renumbers.
    public var index: Int
    public var attributes: [AttributeID: Attribute]

    public init(index: Int, attributes: [AttributeID: Attribute]) {
        self.index = index
        self.attributes = attributes
    }

    /// Read from the message code on the `Type` attribute, not its text, which is localised.
    public var kind: TrackKind {
        switch attributes[.type]?.messageCode {
        case 6201: .video
        case 6202: .audio
        case 6203: .subtitles
        default: .unknown
        }
    }

    public var name: String? { self[.name] }
    public var languageCode: String? { self[.langCode] }
    public var languageName: String? { self[.langName] }
    public var codecId: String? { self[.codecId] }
    public var codecShort: String? { self[.codecShort] }
    public var codecLong: String? { self[.codecLong] }
    public var streamTypeExtension: String? { self[.streamTypeExtension] }
    public var bitrateText: String? { self[.bitrate] }
    public var audioChannelsCount: Int? { integer(.audioChannelsCount) }
    public var audioSampleRate: Int? { integer(.audioSampleRate) }
    public var audioSampleSize: Int? { integer(.audioSampleSize) }
    public var videoSize: String? { self[.videoSize] }
    public var videoAspectRatio: String? { self[.videoAspectRatio] }
    public var videoFrameRate: String? { self[.videoFrameRate] }
    public var streamFlags: Int? { integer(.streamFlags) }
    public var flags: StreamFlags { StreamFlags(rawValue: streamFlags ?? 0) }
    /// MakeMKV made this track out of another: a lossy core, or a forced-only subtitle stream.
    public var isDerived: Bool { flags.contains(.derivedStream) }
    /// A lossless track carrying a lossy core, which follows it as a derived track.
    public var hasCore: Bool { flags.contains(.hasCoreAudio) }
    public var isCore: Bool { flags.contains(.coreAudio) }
    public var isForcedOnly: Bool { flags.contains(.forcedSubtitles) && isDerived }
    /// MakeMKV's own flag letters — `d` for default, and so on.
    public var mkvFlags: String? { self[.mkvFlags] }
    public var mkvFlagsText: String? { self[.mkvFlagsText] }
    public var audioChannelLayoutName: String? { self[.audioChannelLayoutName] }
    public var outputCodecShort: String? { self[.outputCodecShort] }
    public var outputConversionType: String? { self[.outputConversionType] }
}

public enum TrackKind: Hashable, Sendable {
    case video
    case audio
    case subtitles
    case unknown
}
