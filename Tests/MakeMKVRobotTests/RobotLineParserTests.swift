// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import MakeMKVRobot
import XCTest

final class RobotLineParserTests: XCTestCase {
    private func one(_ text: String) -> RobotLine? {
        var parser = RobotLineParser()
        return parser.feed(text)
    }

    func testTitleAttributeKeepsCommaInsideQuotes() {
        let line = one(#"TINFO:0,30,0,"Doctor Who - The Daleks In Colour - Disc 1 - 12 chapter(s) , 21.0 GB""#)
        XCTAssertEqual(
            line,
            .titleAttribute(title: 0, Attribute(id: .treeInfo, messageCode: 0, value: "Doctor Who - The Daleks In Colour - Disc 1 - 12 chapter(s) , 21.0 GB"))
        )
    }

    func testMessageResolvesEscapedQuotesAndParameters() {
        let line = one(#"MSG:2010,0,1,"Optical drive \"BD-RE PIONEER\" opened in OS access mode.","Optical drive \"%1\" opened in OS access mode.","BD-RE PIONEER""#)
        XCTAssertEqual(
            line,
            .message(Message(
                code: 2010,
                flags: 0,
                text: "Optical drive \"BD-RE PIONEER\" opened in OS access mode.",
                format: "Optical drive \"%1\" opened in OS access mode.",
                parameters: ["BD-RE PIONEER"]
            ))
        )
    }

    func testMessageWithMismatchedParameterCountIsUnrecognised() {
        let text = #"MSG:1005,0,2,"x","%1","only one""#
        XCTAssertEqual(one(text), .unrecognised(text))
    }

    func testQuotedStringMayContinueAcrossLines() {
        // The shape MakeMKV writes for a message holding two line breaks: a backslash escapes each.
        var parser = RobotLineParser()
        XCTAssertNil(parser.feed(#"MSG:3334,1288,0,"It appears that you have on-the-fly decryption software enabled. \"#))
        XCTAssertNil(parser.feed(#"\"#))
        let line = parser.feed(#"Do you want to continue anyway?","It appears that you have on-the-fly decryption software enabled. \"#)
        XCTAssertNil(line)
        XCTAssertNil(parser.feed(#"\"#))
        let finished = parser.feed(#"Do you want to continue anyway?""#)
        guard case .message(let message)? = finished else {
            return XCTFail("expected a message, got \(String(describing: finished))")
        }
        XCTAssertEqual(message.code, 3334)
        XCTAssertEqual(message.text, "It appears that you have on-the-fly decryption software enabled. \n\nDo you want to continue anyway?")
        XCTAssertEqual(message.format, message.text)
        XCTAssertEqual(message.parameters, [])
    }

    func testDriveLineDecodesStateAndMediaFlags() {
        let line = one(#"DRV:0,2,999,12,"BD-RE PIONEER","DOCTOR_WHO","/dev/rdisk5""#)
        XCTAssertEqual(
            line,
            .drive(Drive(index: 0, state: .inserted, enabled: 999, media: [.blurayFiles, .aacsFiles], driveName: "BD-RE PIONEER", discName: "DOCTOR_WHO", devicePath: "/dev/rdisk5"))
        )
        guard case .drive(let drive)? = line else { return XCTFail() }
        XCTAssertTrue(drive.hasDisc)
    }

    func testEmptyDriveSlot() {
        let line = one(#"DRV:7,256,999,0,"","","""#)
        guard case .drive(let drive)? = line else { return XCTFail() }
        XCTAssertEqual(drive.state, .noDrive)
        XCTAssertFalse(drive.isPresent)
    }

    func testStreamAttributeCarriesMessageCode() {
        XCTAssertEqual(
            one(#"SINFO:0,1,1,6202,"Audio""#),
            .streamAttribute(title: 0, stream: 1, Attribute(id: .type, messageCode: 6202, value: "Audio"))
        )
    }

    func testDiscAttributeTitleCountAndProgress() {
        XCTAssertEqual(one(#"CINFO:1,6209,"Blu-ray disc""#), .discAttribute(Attribute(id: .type, messageCode: 6209, value: "Blu-ray disc")))
        XCTAssertEqual(one("TCOUNT:10"), .titleCount(10))
        XCTAssertEqual(one(#"PRGC:5017,0,"Saving to MKV file""#), .progressCurrent(ProgressTitle(code: 5017, id: 0, name: "Saving to MKV file")))
        XCTAssertEqual(one(#"PRGT:5018,0,"Saving all titles""#), .progressTotal(ProgressTitle(code: 5018, id: 0, name: "Saving all titles")))
        XCTAssertEqual(one("PRGV:100,200,65536"), .progressValue(ProgressValue(current: 100, total: 200, maximum: 65536)))
    }

    func testUnknownPrefixAndBlankLines() {
        let hsh = "HSH:0,00005.m2ts,1/19/2024 11:48:35 AM,176111616"
        XCTAssertEqual(one(hsh), .unrecognised(hsh))
        XCTAssertNil(one(""))
        XCTAssertNil(one("   "))
        XCTAssertEqual(one("garbage"), .unrecognised("garbage"))
    }

    func testUnknownAttributeIDSurvives() {
        guard case .titleAttribute(_, let attribute)? = one(#"TINFO:0,99,0,"x""#) else { return XCTFail() }
        XCTAssertEqual(attribute.id.rawValue, 99)
        XCTAssertNil(attribute.id.name)
        XCTAssertEqual(AttributeID.segmentsMap.name, "SegmentsMap")
        XCTAssertEqual(AttributeID.segmentsMap.description, "SegmentsMap(26)")
    }

    func testDamagedLineDoesNotSwallowWhatFollows() {
        // A log truncated at the top, so it opens mid-message with an unbalanced quote.
        let lines = RobotLineParser.parse("""
            \\
            Do you want to continue anyway (errors may follow) ?","It appears that you have
            TCOUNT:1
            """)
        XCTAssertEqual(lines, [
            .unrecognised("\\"),
            .unrecognised(#"Do you want to continue anyway (errors may follow) ?","It appears that you have"#),
            .titleCount(1),
        ])
    }

    func testParseDocumentFlushesTrailingLine() {
        let lines = RobotLineParser.parse("TCOUNT:1\nCINFO:2,0,\"Name\"")
        XCTAssertEqual(lines, [.titleCount(1), .discAttribute(Attribute(id: .name, messageCode: 0, value: "Name"))])
    }
}
