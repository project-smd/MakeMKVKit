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

    static let knownPrefixes: Set<Substring> = [
        "MSG", "PRGC", "PRGT", "PRGV", "DRV", "TCOUNT", "CINFO", "TINFO", "SINFO",
    ]

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

        // Every reader below returns `nil` on a shape it cannot read, which becomes
        // `.unrecognised(line)`, so a malformed line is surfaced rather than swallowed or turned into
        // a half-filled value.
        let parsed: RobotLine?
        switch prefix {
        case "MSG": parsed = message(fields(payload))
        case "PRGC": parsed = progressTitle(fields(payload)).map(RobotLine.progressCurrent)
        case "PRGT": parsed = progressTitle(fields(payload)).map(RobotLine.progressTotal)
        case "PRGV": parsed = progressValue(fields(payload))
        case "DRV": parsed = drive(fields(payload))
        case "TCOUNT": parsed = Int(payload).map(RobotLine.titleCount)
        case "CINFO": parsed = discAttribute(fields(payload))
        case "TINFO": parsed = titleAttribute(fields(payload))
        case "SINFO": parsed = streamAttribute(fields(payload))
        default: parsed = nil
        }
        return parsed ?? .unrecognised(line)
    }

    // MARK: - Line kinds

    private static func message(_ fields: [String]) -> RobotLine? {
        guard fields.count >= 5, let code = Int(fields[0]), let flags = UInt32(fields[1]), let count = Int(fields[2])
        else {
            return nil
        }
        let parameters = Array(fields.dropFirst(5))
        guard parameters.count == count else {
            return nil
        }
        return .message(
            Message(code: code, flags: flags, text: fields[3], format: fields[4], parameters: parameters)
        )
    }

    private static func progressTitle(_ fields: [String]) -> ProgressTitle? {
        guard fields.count == 3, let code = Int(fields[0]), let id = Int(fields[1]) else {
            return nil
        }
        return ProgressTitle(code: code, id: id, name: fields[2])
    }

    private static func progressValue(_ fields: [String]) -> RobotLine? {
        guard fields.count == 3, let current = Int(fields[0]), let total = Int(fields[1]),
            let maximum = Int(fields[2])
        else {
            return nil
        }
        return .progressValue(ProgressValue(current: current, total: total, maximum: maximum))
    }

    private static func drive(_ fields: [String]) -> RobotLine? {
        // Six fields in older versions, seven once the device path was added.
        guard fields.count == 6 || fields.count == 7,
            let index = Int(fields[0]), let state = Int(fields[1]), let enabled = Int(fields[2]),
            let flags = Int(fields[3])
        else {
            return nil
        }
        return .drive(
            Drive(
                index: index,
                state: DriveState(rawValue: state),
                enabled: enabled,
                media: MediaFlags(rawValue: flags),
                driveName: fields[4],
                discName: fields[5],
                devicePath: fields.count == 7 ? fields[6] : ""
            )
        )
    }

    private static func discAttribute(_ fields: [String]) -> RobotLine? {
        guard fields.count == 3, let id = Int(fields[0]), let code = Int(fields[1]) else {
            return nil
        }
        return .discAttribute(Attribute(id: AttributeID(rawValue: id), messageCode: code, value: fields[2]))
    }

    private static func titleAttribute(_ fields: [String]) -> RobotLine? {
        guard fields.count == 4, let title = Int(fields[0]), let id = Int(fields[1]), let code = Int(fields[2]) else {
            return nil
        }
        return .titleAttribute(
            title: title,
            Attribute(id: AttributeID(rawValue: id), messageCode: code, value: fields[3])
        )
    }

    private static func streamAttribute(_ fields: [String]) -> RobotLine? {
        guard fields.count == 5, let title = Int(fields[0]), let stream = Int(fields[1]), let id = Int(fields[2]),
            let code = Int(fields[3])
        else {
            return nil
        }
        return .streamAttribute(
            title: title,
            stream: stream,
            Attribute(id: AttributeID(rawValue: id), messageCode: code, value: fields[4])
        )
    }
}
