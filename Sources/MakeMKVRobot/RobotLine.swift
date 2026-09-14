// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

/// One logical line of `makemkvcon -r` output, as documented at makemkv.com/developers.
///
/// A logical line is usually one physical line. It is not when a quoted string contains a line
/// break, which MakeMKV writes as a backslash followed by the break; `RobotLineParser` joins those
/// before anything here sees them.
public enum RobotLine: Hashable, Sendable {
    /// `MSG:code,flags,count,message,format,param0,…`
    case message(Message)
    /// `PRGC:code,id,name` — the current-operation caption.
    case progressCurrent(ProgressTitle)
    /// `PRGT:code,id,name` — the whole-job caption.
    case progressTotal(ProgressTitle)
    /// `PRGV:current,total,max`
    case progressValue(ProgressValue)
    /// `DRV:index,visible,enabled,flags,driveName,discName,devicePath`
    case drive(Drive)
    /// `TCOUNT:count`
    case titleCount(Int)
    /// `CINFO:id,code,value` — an attribute of the disc.
    case discAttribute(Attribute)
    /// `TINFO:title,id,code,value` — an attribute of one title.
    case titleAttribute(title: Int, Attribute)
    /// `SINFO:title,stream,id,code,value` — an attribute of one stream of one title.
    case streamAttribute(title: Int, stream: Int, Attribute)
    /// Anything else, verbatim. TheDiscDb appends `HSH:` lines to the logs it keeps; those land
    /// here, as does any malformed line, so nothing is silently dropped.
    case unrecognised(String)
}

/// A `MSG` line. `text` is the rendered message; `format` and `parameters` are the template and
/// its arguments, which is what a caller should match on when it needs a fact rather than prose.
public struct Message: Hashable, Sendable {
    public var code: Int
    public var flags: UInt32
    public var text: String
    public var format: String
    public var parameters: [String]

    public init(code: Int, flags: UInt32, text: String, format: String, parameters: [String]) {
        self.code = code
        self.flags = flags
        self.text = text
        self.format = format
        self.parameters = parameters
    }

    // Flag bits from the AP_UIMSG_* constants in apdefs.h.
    public var isDebug: Bool { flags & 32 != 0 }
    public var isHidden: Bool { flags & 64 != 0 }
    public var isEvent: Bool { flags & 128 != 0 }
}

public struct ProgressTitle: Hashable, Sendable {
    public var code: Int
    public var id: Int
    public var name: String

    public init(code: Int, id: Int, name: String) {
        self.code = code
        self.id = id
        self.name = name
    }
}

public struct ProgressValue: Hashable, Sendable {
    public var current: Int
    public var total: Int
    public var maximum: Int

    public init(current: Int, total: Int, maximum: Int) {
        self.current = current
        self.total = total
        self.maximum = maximum
    }

    /// `current` as a fraction of `maximum`, or `nil` when `maximum` is zero.
    public var currentFraction: Double? {
        maximum > 0 ? Double(current) / Double(maximum) : nil
    }

    public var totalFraction: Double? {
        maximum > 0 ? Double(total) / Double(maximum) : nil
    }
}

/// A `DRV` line. MakeMKV always prints sixteen of them, one per possible slot; a slot with no drive
/// has `state == .noDrive` and empty strings.
public struct Drive: Hashable, Sendable {
    public var index: Int
    public var state: DriveState
    public var enabled: Int
    public var media: MediaFlags
    public var driveName: String
    public var discName: String
    public var devicePath: String

    public init(index: Int, state: DriveState, enabled: Int, media: MediaFlags, driveName: String, discName: String, devicePath: String) {
        self.index = index
        self.state = state
        self.enabled = enabled
        self.media = media
        self.driveName = driveName
        self.discName = discName
        self.devicePath = devicePath
    }

    public var isPresent: Bool { state != .noDrive }
    public var hasDisc: Bool { state == .inserted }
}

/// The `visible` field of a `DRV` line; values are the `AP_DriveState*` constants in apdefs.h.
public struct DriveState: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let emptyClosed = DriveState(rawValue: 0)
    public static let emptyOpen = DriveState(rawValue: 1)
    public static let inserted = DriveState(rawValue: 2)
    public static let loading = DriveState(rawValue: 3)
    public static let noDrive = DriveState(rawValue: 256)
    public static let unmounting = DriveState(rawValue: 257)
}

/// The `flags` field of a `DRV` line; bits are the `AP_DskFsFlag*` constants in apdefs.h.
public struct MediaFlags: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let dvdFiles = MediaFlags(rawValue: 1)
    public static let hdDVDFiles = MediaFlags(rawValue: 2)
    public static let blurayFiles = MediaFlags(rawValue: 4)
    public static let aacsFiles = MediaFlags(rawValue: 8)
    public static let bdsvmFiles = MediaFlags(rawValue: 16)
}

/// One attribute of the disc, a title or a stream.
///
/// `messageCode` is non-zero when the value is a localised string with a stable numeric identity —
/// a stream's type is `6201`, `6202` or `6203` whether the text says "Audio" or something else —
/// and zero when the value is free text. Match on the code, not the text, wherever one exists.
public struct Attribute: Hashable, Sendable {
    public var id: AttributeID
    public var messageCode: Int
    public var value: String

    public init(id: AttributeID, messageCode: Int, value: String) {
        self.id = id
        self.messageCode = messageCode
        self.value = value
    }
}
