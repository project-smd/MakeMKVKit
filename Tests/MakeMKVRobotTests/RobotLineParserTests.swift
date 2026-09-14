// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import MakeMKVRobot
import Testing

struct RobotLineParserTests {
    private func one(_ text: String) -> RobotLine? {
        var parser = RobotLineParser()
        return parser.feed(text)
    }

    @Test func titleAttributeKeepsCommaInsideQuotes() {
        let line = one(#"TINFO:0,30,0,"Doctor Who - The Daleks In Colour - Disc 1 - 12 chapter(s) , 21.0 GB""#)
        #expect(line == .titleAttribute(title: 0, Attribute(id: .treeInfo, messageCode: 0, value: "Doctor Who - The Daleks In Colour - Disc 1 - 12 chapter(s) , 21.0 GB")))
    }

    @Test func messageResolvesEscapedQuotesAndParameters() {
        let line = one(#"MSG:2010,0,1,"Optical drive \"BD-RE PIONEER\" opened in OS access mode.","Optical drive \"%1\" opened in OS access mode.","BD-RE PIONEER""#)
        #expect(line == .message(Message(
            code: 2010,
            flags: 0,
            text: "Optical drive \"BD-RE PIONEER\" opened in OS access mode.",
            format: "Optical drive \"%1\" opened in OS access mode.",
            parameters: ["BD-RE PIONEER"]
        )))
    }

    @Test func messageWithMismatchedParameterCountIsUnrecognised() {
        let text = #"MSG:1005,0,2,"x","%1","only one""#
        #expect(one(text) == .unrecognised(text))
    }

    @Test func quotedStringMayContinueAcrossLines() throws {
        // The shape MakeMKV writes for a message holding two line breaks: a backslash escapes each.
        var parser = RobotLineParser()
        #expect(parser.feed(#"MSG:3334,1288,0,"It appears that you have on-the-fly decryption software enabled. \"#) == nil)
        #expect(parser.feed(#"\"#) == nil)
        #expect(parser.feed(#"Do you want to continue anyway?","It appears that you have on-the-fly decryption software enabled. \"#) == nil)
        #expect(parser.feed(#"\"#) == nil)
        let finished = parser.feed(#"Do you want to continue anyway?""#)
        guard case .message(let message)? = finished else {
            Issue.record("expected a message, got \(String(describing: finished))")
            return
        }
        #expect(message.code == 3334)
        #expect(message.text == "It appears that you have on-the-fly decryption software enabled. \n\nDo you want to continue anyway?")
        #expect(message.format == message.text)
        #expect(message.parameters == [])
    }

    @Test func driveLineDecodesStateAndMediaFlags() throws {
        let line = one(#"DRV:0,2,999,12,"BD-RE PIONEER","DOCTOR_WHO","/dev/rdisk5""#)
        #expect(line == .drive(Drive(index: 0, state: .inserted, enabled: 999, media: [.blurayFiles, .aacsFiles], driveName: "BD-RE PIONEER", discName: "DOCTOR_WHO", devicePath: "/dev/rdisk5")))
        guard case .drive(let drive)? = line else {
            Issue.record("not a drive line")
            return
        }
        #expect(drive.hasDisc)
    }

    @Test func emptyDriveSlot() {
        guard case .drive(let drive)? = one(#"DRV:7,256,999,0,"","","""#) else {
            Issue.record("not a drive line")
            return
        }
        #expect(drive.state == .noDrive)
        #expect(!drive.isPresent)
    }

    @Test func streamAttributeCarriesMessageCode() {
        #expect(one(#"SINFO:0,1,1,6202,"Audio""#) == .streamAttribute(title: 0, stream: 1, Attribute(id: .type, messageCode: 6202, value: "Audio")))
    }

    @Test func discAttributeTitleCountAndProgress() {
        #expect(one(#"CINFO:1,6209,"Blu-ray disc""#) == .discAttribute(Attribute(id: .type, messageCode: 6209, value: "Blu-ray disc")))
        #expect(one("TCOUNT:10") == .titleCount(10))
        #expect(one(#"PRGC:5017,0,"Saving to MKV file""#) == .progressCurrent(ProgressTitle(code: 5017, id: 0, name: "Saving to MKV file")))
        #expect(one(#"PRGT:5018,0,"Saving all titles""#) == .progressTotal(ProgressTitle(code: 5018, id: 0, name: "Saving all titles")))
        #expect(one("PRGV:100,200,65536") == .progressValue(ProgressValue(current: 100, total: 200, maximum: 65536)))
    }

    @Test func unknownPrefixAndBlankLines() {
        let hsh = "HSH:0,00005.m2ts,1/19/2024 11:48:35 AM,176111616"
        #expect(one(hsh) == .unrecognised(hsh))
        #expect(one("") == nil)
        #expect(one("   ") == nil)
        #expect(one("garbage") == .unrecognised("garbage"))
    }

    @Test func unknownAttributeIDSurvives() {
        guard case .titleAttribute(_, let attribute)? = one(#"TINFO:0,99,0,"x""#) else {
            Issue.record("not a title attribute")
            return
        }
        #expect(attribute.id.rawValue == 99)
        #expect(attribute.id.name == nil)
        #expect(AttributeID.segmentsMap.name == "SegmentsMap")
        #expect(AttributeID.segmentsMap.description == "SegmentsMap(26)")
    }

    @Test func damagedLineDoesNotSwallowWhatFollows() {
        // A log truncated at the top, so it opens mid-message with an unbalanced quote.
        let lines = RobotLineParser.parse("""
            \\
            Do you want to continue anyway (errors may follow) ?","It appears that you have
            TCOUNT:1
            """)
        #expect(lines == [
            .unrecognised("\\"),
            .unrecognised(#"Do you want to continue anyway (errors may follow) ?","It appears that you have"#),
            .titleCount(1),
        ])
    }

    @Test func parseDocumentFlushesTrailingLine() {
        let lines = RobotLineParser.parse("TCOUNT:1\nCINFO:2,0,\"Name\"")
        #expect(lines == [.titleCount(1), .discAttribute(Attribute(id: .name, messageCode: 0, value: "Name"))])
    }
}
