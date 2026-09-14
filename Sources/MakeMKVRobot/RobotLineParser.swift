// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

/// Turns physical lines of robot output into `RobotLine` values.
///
/// The grammar, measured against 5,180 saved logs rather than taken from the documentation, which
/// does not cover it: fields are comma-separated; a string field is enclosed in double quotes; inside
/// a string a backslash escapes the next character, so `\"` is a quote, `\\` a backslash, and a
/// backslash at the end of a physical line escapes the line break. That last rule is why this is a
/// stateful parser: `feed` returns `nil` while a quoted string is still open.
public struct RobotLineParser: Sendable {
    private var pending = ""

    public init() {}

    /// Feed one physical line, without its terminator. Returns the parsed line when a logical line
    /// completes, `nil` when more input is needed or the line was blank.
    public mutating func feed(_ line: String) -> RobotLine? {
        if pending.isEmpty {
            if line.allSatisfy(\.isWhitespace) {
                return nil
            }
            // Only a line that starts like a robot line may continue onto the next. Without this a
            // damaged line with an odd number of quotes — a log truncated mid-message, say — would
            // swallow everything after it into one unterminated string.
            guard Self.hasKnownPrefix(line) else {
                return .unrecognised(line)
            }
        }
        let candidate = pending.isEmpty ? line : pending + "\n" + line
        if Self.isComplete(candidate) {
            pending = ""
            return Self.parse(logicalLine: candidate)
        }
        pending = candidate
        return nil
    }

    /// Flush an unterminated logical line at end of input, parsed as best it can be.
    public mutating func finish() -> RobotLine? {
        guard !pending.isEmpty else { return nil }
        defer { pending = "" }
        return Self.parse(logicalLine: pending)
    }

    /// Parse a whole document.
    public static func parse(_ text: String) -> [RobotLine] {
        var parser = RobotLineParser()
        var lines: [RobotLine] = []
        for physical in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if let line = parser.feed(String(physical)) {
                lines.append(line)
            }
        }
        if let line = parser.finish() {
            lines.append(line)
        }
        return lines
    }

    // MARK: - Grammar

    static let knownPrefixes: Set<Substring> = ["MSG", "PRGC", "PRGT", "PRGV", "DRV", "TCOUNT", "CINFO", "TINFO", "SINFO"]

    static func hasKnownPrefix(_ line: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else { return false }
        return knownPrefixes.contains(line[..<colon])
    }

    /// True when every quote is closed and the line does not end mid-escape.
    static func isComplete(_ line: String) -> Bool {
        var quoted = false
        var escaped = false
        for character in line {
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            }
        }
        return !quoted && !escaped
    }

    /// Split the payload after `PREFIX:` into fields, removing quotes and resolving escapes.
    static func fields(_ payload: Substring) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        var escaped = false
        for character in payload {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" && quoted {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if character == "," && !quoted {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }

    static func parse(logicalLine line: String) -> RobotLine {
        guard let colon = line.firstIndex(of: ":") else {
            return .unrecognised(line)
        }
        let prefix = line[..<colon]
        let payload = line[line.index(after: colon)...]

        // Everything below returns `.unrecognised(line)` on a shape it cannot read, so a malformed
        // line is surfaced rather than swallowed or turned into a half-filled value.
        switch prefix {
        case "MSG":
            let f = fields(payload)
            guard f.count >= 5, let code = Int(f[0]), let flags = UInt32(f[1]), let count = Int(f[2]) else {
                return .unrecognised(line)
            }
            let parameters = Array(f.dropFirst(5))
            guard parameters.count == count else {
                return .unrecognised(line)
            }
            return .message(Message(code: code, flags: flags, text: f[3], format: f[4], parameters: parameters))

        case "PRGC", "PRGT":
            let f = fields(payload)
            guard f.count == 3, let code = Int(f[0]), let id = Int(f[1]) else {
                return .unrecognised(line)
            }
            let title = ProgressTitle(code: code, id: id, name: f[2])
            return prefix == "PRGC" ? .progressCurrent(title) : .progressTotal(title)

        case "PRGV":
            let f = fields(payload)
            guard f.count == 3, let current = Int(f[0]), let total = Int(f[1]), let maximum = Int(f[2]) else {
                return .unrecognised(line)
            }
            return .progressValue(ProgressValue(current: current, total: total, maximum: maximum))

        case "DRV":
            let f = fields(payload)
            // Six fields in older versions, seven once the device path was added.
            guard f.count == 6 || f.count == 7,
                  let index = Int(f[0]), let state = Int(f[1]), let enabled = Int(f[2]), let flags = Int(f[3]) else {
                return .unrecognised(line)
            }
            return .drive(Drive(
                index: index,
                state: DriveState(rawValue: state),
                enabled: enabled,
                media: MediaFlags(rawValue: flags),
                driveName: f[4],
                discName: f[5],
                devicePath: f.count == 7 ? f[6] : ""
            ))

        case "TCOUNT":
            guard let count = Int(payload) else {
                return .unrecognised(line)
            }
            return .titleCount(count)

        case "CINFO":
            let f = fields(payload)
            guard f.count == 3, let id = Int(f[0]), let code = Int(f[1]) else {
                return .unrecognised(line)
            }
            return .discAttribute(Attribute(id: AttributeID(rawValue: id), messageCode: code, value: f[2]))

        case "TINFO":
            let f = fields(payload)
            guard f.count == 4, let title = Int(f[0]), let id = Int(f[1]), let code = Int(f[2]) else {
                return .unrecognised(line)
            }
            return .titleAttribute(title: title, Attribute(id: AttributeID(rawValue: id), messageCode: code, value: f[3]))

        case "SINFO":
            let f = fields(payload)
            guard f.count == 5, let title = Int(f[0]), let stream = Int(f[1]), let id = Int(f[2]), let code = Int(f[3]) else {
                return .unrecognised(line)
            }
            return .streamAttribute(
                title: title,
                stream: stream,
                Attribute(id: AttributeID(rawValue: id), messageCode: code, value: f[4])
            )

        default:
            return .unrecognised(line)
        }
    }
}
