// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

/// A track selection rule in MakeMKV's own language, the string the GUI calls the default
/// selection rule and a conversion profile carries as `defaultSelection`.
///
/// The vocabulary is MakeMKV's, from its forum post documenting the syntax (topic 4386), and the
/// names here are its names so the two can be read against each other. A rule is a list of
/// actions applied in order, each to the tracks its condition matches; a later action overrides an
/// earlier one, which is why the shipped default starts by deselecting everything.
public struct SelectionRule: Hashable, Sendable, CustomStringConvertible {
    /// The keywords a condition may test. Each doc comment is MakeMKV's own definition.
    public enum Attribute: String, Hashable, Sendable, CaseIterable {
        /// always matches
        case all
        /// matches if track is video
        case video
        /// matches if track is audio
        case audio
        /// matches if track is subtitle
        case subtitle
        /// matches favorite languages, always matches if no favorite language is set
        case favlang
        /// matches if track has no language
        case nolang
        /// matches if track is the only one of its type and language
        case single
        /// matches if track is special (directors comments, childrens, etc)
        case special
        /// matches if mono
        case mono
        /// matches if stereo
        case stereo
        /// matches if multi-channel
        case multi
        /// matches if track is mono/stereo and there is a multi-channel track in same language
        case havemulti
        /// matches if non-lossless
        case lossy
        /// matches if lossless
        case lossless
        /// matches if non-lossless track, but there is a lossless track in same language
        case havelossless
        /// matches if this track is core audio, logical part of hd track
        ///
        /// Measured: `+sel:all,-sel:core` keeps the DTS-HD MA track and drops its DTS core.
        case core
        /// matches if this track is hd track with core audio
        ///
        /// Measured: `+sel:all,-sel:havecore` keeps the DTS core and drops the DTS-HD MA track. So
        /// the shipped default rule, which deselects `havecore`, keeps the lossy core, not the
        /// lossless track.
        case havecore
        /// matches if track is forced
        case forced
        /// matches if track is a 3D multi-view video
        case mvcvideo
    }

    public indirect enum Condition: Hashable, Sendable {
        case attribute(Attribute)
        /// An ISO 639-2 code: `eng`, `fra`.
        case language(String)
        /// Matches the Nth or later track of the same type and language.
        case nth(Int)
        case not(Condition)
        /// All of these: `(a*b*c)`.
        case allOf([Condition])
        /// Any of these: `(a|b|c)`.
        case anyOf([Condition])

        public static func and(_ lhs: Condition, _ rhs: Condition) -> Condition { .allOf([lhs, rhs]) }
        public static func or(_ lhs: Condition, _ rhs: Condition) -> Condition { .anyOf([lhs, rhs]) }

        /// The rule text. `*` stands in for `&`, MakeMKV's own alias, because the rule usually
        /// ends up inside an XML attribute where an ampersand is a nuisance.
        var text: String {
            switch self {
            case .attribute(let attribute): attribute.rawValue
            case .language(let code): code
            case .nth(let n): String(n)
            case .not(let inner): "!" + inner.text
            case .allOf(let parts): "(" + parts.map(\.text).joined(separator: "*") + ")"
            case .anyOf(let parts): "(" + parts.map(\.text).joined(separator: "|") + ")"
            }
        }
    }

    public enum Action: Hashable, Sendable {
        /// `+sel`
        case select(Condition)
        /// `-sel`
        case deselect(Condition)
        /// `=N`
        case setWeight(Int, Condition)
        /// `+N`
        case addWeight(Int, Condition)
        /// `-N`
        case subtractWeight(Int, Condition)

        var text: String {
            switch self {
            case .select(let condition): "+sel:\(condition.text)"
            case .deselect(let condition): "-sel:\(condition.text)"
            case .setWeight(let weight, let condition): "=\(weight):\(condition.text)"
            case .addWeight(let weight, let condition): "+\(weight):\(condition.text)"
            case .subtractWeight(let weight, let condition): "-\(weight):\(condition.text)"
            }
        }
    }

    public var actions: [Action]

    public init(_ actions: [Action]) {
        self.actions = actions
    }

    /// The rule as MakeMKV reads it.
    public var description: String {
        actions.map(\.text).joined(separator: ",")
    }

    /// What ships in MakeMKV's own `default.mmcp.xml`: favourite languages only, no stereo track
    /// where a multi-channel one exists, no HD track that carries a core, no 3D video.
    public static let makeMKVDefault = SelectionRule([
        .deselect(.attribute(.all)),
        .select(.anyOf([.attribute(.favlang), .attribute(.nolang), .attribute(.single)])),
        .deselect(.anyOf([.attribute(.havemulti), .attribute(.havecore)])),
        .deselect(.attribute(.mvcvideo)),
        .setWeight(100, .attribute(.all)),
        .subtractWeight(10, .attribute(.favlang)),
    ])

    /// Every track on the disc, as it is.
    public static let everything = SelectionRule([.select(.attribute(.all))])
}
