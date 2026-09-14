// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import Foundation

/// A MakeMKV conversion profile: the `.mmcp.xml` file `--profile` takes, and the per-run way to
/// say which tracks a rip keeps.
///
/// The document mirrors the `default.mmcp.xml` MakeMKV ships in its application data, rule for
/// rule — copy every track as it is, raw LPCM for stereo LPCM, WAVEX for multi-channel LPCM — with
/// one difference: the selection is written into each rule as a literal rather than as a reference
/// to the installed preference. That is the whole point. The installed preference is whatever this
/// machine's GUI last saved, and a rip that depends on it is not reproducible.
public struct ConversionProfile: Hashable, Sendable {
    public var name: String
    public var selection: SelectionRule

    public init(name: String = "MakeMKVKit", selection: SelectionRule) {
        self.name = name
        self.selection = selection
    }

    /// The profile document.
    public var xml: String {
        let rule = Self.escape(selection.description)
        let title = Self.escape(name)
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <!-- Written by MakeMKVKit. Mirrors MakeMKV's default.mmcp.xml with the selection rule
             inlined, so the same profile selects the same tracks on any machine. -->
        <profile>
            <name lang="eng">\(title)</name>
            <mkvSettings
                ignoreForcedSubtitlesFlag="true"
                useISO639Type2T="false"
                setFirstAudioTrackAsDefault="true"
                setFirstSubtitleTrackAsDefault="true"
                setFirstForcedSubtitleTrackAsDefault="true"
                insertFirstChapter00IfMissing="true"
            />
            <outputSettings name="copy" outputFormat="directCopy">
                <description lang="eng">Copy track as is</description>
            </outputSettings>
            <outputSettings name="lpcm" outputFormat="LPCM-raw">
                <description lang="eng">Save as raw LPCM</description>
            </outputSettings>
            <outputSettings name="wavex" outputFormat="LPCM-wavex">
                <description lang="eng">Save as LPCM in WAV container</description>
            </outputSettings>
            <trackSettings input="default">
                <output outputSettingsName="copy" defaultSelection="\(rule)"/>
            </trackSettings>
            <trackSettings input="LPCM-stereo">
                <output outputSettingsName="lpcm" defaultSelection="\(rule)"/>
            </trackSettings>
            <trackSettings input="LPCM-multi">
                <output outputSettingsName="wavex" defaultSelection="\(rule)"/>
            </trackSettings>
        </profile>

        """
    }

    /// Write the document to a file MakeMKV can be pointed at.
    public func write(to url: URL) throws {
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Write the document to a fresh file in the temporary directory and return it.
    public func writeToTemporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("makemkvkit-\(UUID().uuidString)")
            .appendingPathExtension("mmcp.xml")
        try write(to: url)
        return url
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
