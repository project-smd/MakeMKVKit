// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import Foundation

/// The wire protocol MakeMKV's own GUI speaks to the engine it spawns as `makemkvcon guiserver`.
///
/// Not documented by MakeMKV. Everything here is read from the open-source half of MakeMKV
/// 1.18.4: the command enum and ABI tag from `aproxy.h`, which its authors placed in the public
/// domain, and the framing from `clt_pipe.cpp`. The engine checks the ABI tag exactly, so a future
/// MakeMKV that bumps it will refuse this client outright rather than misbehave; that is the
/// honest failure mode for an unpublished protocol, and it is reported as such.
public enum EngineProtocol {
    static let abiVersion = "A0001"

    /// One frame: a command byte, up to 32 numeric arguments, and a string buffer.
    public struct Frame: Sendable {
        public var command: Command
        public var args: [UInt32]
        public var data: Data

        public init(_ command: Command, args: [UInt32] = [], data: Data = Data()) {
            self.command = command
            self.args = args
            self.data = data
        }

        /// A NUL-terminated UTF-8 string as the engine passes them, or `nil` for none.
        public init(_ command: Command, args: [UInt32] = [], string: String?) {
            self.init(command, args: args, data: string.map { Data($0.utf8) + [0] } ?? Data())
        }

        /// `args[i]` and `args[i+1]` as one 64-bit handle, the engine's item identity.
        public func handle(at index: Int) -> UInt64 {
            UInt64(args[index]) | (UInt64(args[index + 1]) << 32)
        }

        /// The string buffer as text, up to its first NUL.
        public var string: String {
            let bytes = data.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }

        /// Several NUL-terminated strings packed one after another.
        public var strings: [String] {
            data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        }

        /// The bytes as sent over the pipe. A command with no arguments and no data goes as one
        /// byte, `0xf0 | command`, which is the engine's own shorthand and it expects it back.
        public var encoded: Data {
            let header = (UInt32(command.rawValue) << 24) | (UInt32(args.count) << 16) | UInt32(data.count & 0xffff)
            if args.isEmpty, data.isEmpty, command.rawValue < 0x10 {
                return Data([0xf0 | command.rawValue])
            }
            var out = Data(capacity: 4 + args.count * 4 + data.count)
            for word in [header] + args {
                withUnsafeBytes(of: word.littleEndian) { out.append(contentsOf: $0) }
            }
            out.append(data)
            return out
        }
    }

    /// `AP_CMD`. Calls go to the engine; `back*` come from it in reply to any call, each expecting
    /// `clientDone` before the engine continues, until `return` closes the exchange.
    public enum Command: UInt8, Sendable {
        case nop = 0
        case `return` = 1
        case clientDone = 2
        case callSignalExit = 3
        case callOnIdle = 4
        case callCancelAllJobs = 5

        case callSetOutputFolder = 16
        case callUpdateAvailableDrives = 17
        case callOpenFile = 18
        case callOpenCdDisk = 19
        case callOpenTitleCollection = 20
        case callCloseDisk = 21
        case callEjectDisk = 22
        case callSaveAllSelectedTitlesToMkv = 23
        case callGetUiItemState = 24
        case callSetUiItemState = 25
        case callGetUiItemInfo = 26
        case callGetSettingInt = 27
        case callGetSettingString = 28
        case callSetSettingInt = 29
        case callSetSettingString = 30
        case callSaveSettings = 31
        case callAppGetString = 32
        case callBackupDisc = 33
        case callGetInterfaceLanguageData = 34
        case callSetUiItemInfo = 35
        case callSetProfile = 36
        case callInitMMBD = 37
        case callOpenMMBD = 38
        case callDiscInfoMMBD = 39
        case callDecryptUnitMMBD = 40
        case callSetExternAppFlags = 41
        case callManageState = 42
        case callAppSetString = 43

        case backEnterJobMode = 192
        case backLeaveJobMode = 193
        case backUpdateDrive = 194
        case backUpdateCurrentBar = 195
        case backUpdateTotalBar = 196
        case backUpdateLayout = 197
        case backSetTotalName = 198
        case backUpdateCurrentInfo = 199
        case backReportUiMessage = 200
        case backExit = 201
        case backSetTitleCollInfo = 202
        case backSetTitleInfo = 203
        case backSetTrackInfo = 204
        case backSetChapterInfo = 205
        case backReportUiDialog = 206

        case backFatalCommError = 224
        case backOutOfMem = 225
        case unknown = 239
    }

    /// `ApSettingId`, by position in the enum in `apdefs.h`.
    public enum Setting: UInt32 {
        case dvdMinimumTitleLength = 1
        case appDataDir = 4
        case appDestinationType = 14
        case appDestinationDir = 15
        case appPreferredLanguage = 18
        case appDefaultProfileName = 31
        case appDefaultSelectionString = 32
        case appDefaultOutputFileName = 40
    }

    /// `AP_vastr_*`: the strings `callAppGetString` answers with.
    public enum AppString: UInt32 {
        case name = 0
        case version = 1
        case platform = 2
        case build = 3
        case keyType = 4
        case keyFeatures = 5
        case keyExpiration = 6
        case evalState = 7
        case profileCount = 12
        case outputFolderName = 14
        case outputBaseName = 15
        case currentProfile = 16
        case defaultSelectionString = 20
        case defaultOutputFileName = 21
        case profileString = 24
    }

    /// Adding this to a message code asks `callAppGetString` for that message's text, which is
    /// how libmmbd resolves codes and how this client turns a coded attribute into its text.
    static let messageStringBase: UInt32 = 0x10000

    /// `APP_TTREE_ATTACHMENT`: the type code of a cover-art item the engine lists among tracks.
    static let attachmentTypeCode = 6214

    /// `AP_MaxCdromDevices`: passed to `callCloseDisk` to mean "close, eject nothing".
    static let maxDrives: UInt32 = 16
    static let progressMaximum = 65536

    /// Bits of a UI item's state word.
    static let itemEnabledBit: UInt32 = 1 << 0
    static let itemExpandedBit: UInt32 = 1 << 1
    static let itemStateKnownBit: UInt32 = 1 << 7
}
