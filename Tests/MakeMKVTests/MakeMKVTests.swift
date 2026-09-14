// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import Foundation
import MakeMKV
import MakeMKVRobot
import Testing

/// Everything here runs without a MakeMKV installation or a drive. The driver's process handling is
/// exercised against a real disc by hand; what can be checked offline is what it would ask for.
struct MakeMKVTests {
    @Test func sourceArguments() {
        #expect(Source.disc(0).argument == "disc:0")
        #expect(Source.device("/dev/rdisk5").argument == "dev:/dev/rdisk5")
        #expect(Source.iso(URL(fileURLWithPath: "/tmp/a.iso")).argument == "iso:/tmp/a.iso")
        #expect(Source.folder(URL(fileURLWithPath: "/tmp/backup")).argument == "file:/tmp/backup")
    }

    @Test func scanSettingsArgumentsInFixedOrder() {
        #expect(ScanSettings().arguments == [])
        let settings = ScanSettings(
            minimumTitleLength: 0,
            cacheMegabytes: 1024,
            directIO: true,
            noScan: true,
            additionalArguments: ["--debug"]
        )
        #expect(settings.arguments == ["--minlength=0", "--cache=1024", "--directio=true", "--noscan", "--debug"])
    }

    @Test func selectionRuleReproducesMakeMKVsDefault() {
        // The string in MakeMKV's own default.mmcp.xml, character for character.
        #expect(SelectionRule.makeMKVDefault.description == "-sel:all,+sel:(favlang|nolang|single),-sel:(havemulti|havecore),-sel:mvcvideo,=100:all,-10:favlang")
        #expect(SelectionRule.everything.description == "+sel:all")
        let rule = SelectionRule([
            .select(.attribute(.all)),
            .deselect(.attribute(.core)),
            .deselect(.and(.attribute(.subtitle), .attribute(.forced))),
            .deselect(.not(.language("eng"))),
            .addWeight(5, .nth(2)),
        ])
        #expect(rule.description == "+sel:all,-sel:core,-sel:(subtitle*forced),-sel:!eng,+5:2")
    }

    @Test func conversionProfileInlinesTheRuleAndWrites() throws {
        let profile = ConversionProfile(name: "Test & <check>", selection: SelectionRule([.select(.attribute(.all)), .deselect(.attribute(.core))]))
        let xml = profile.xml
        #expect(xml.contains(#"defaultSelection="+sel:all,-sel:core""#))
        #expect(xml.components(separatedBy: "defaultSelection=").count == 4, "one per trackSettings rule, as in the shipped default")
        #expect(xml.contains("<name lang=\"eng\">Test &amp; &lt;check></name>"))
        #expect(!xml.contains("$app_DefaultSelectionString"))

        let url = try profile.writeToTemporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.pathExtension == "xml")
        #expect(try String(contentsOf: url, encoding: .utf8) == xml)
        // It is well-formed XML.
        _ = try XMLDocument(contentsOf: url)
    }

    @Test func locateReportsWhereItLooked() throws {
        let error = try #require(throws: MakeMKVError.self) {
            try MakeMKV.locate(defaultLocations: [URL(fileURLWithPath: "/nonexistent/makemkvcon")], environment: ["PATH": "/nonexistent/bin"])
        }
        guard case .executableNotFound(let searched) = error else {
            Issue.record("unexpected \(error)")
            return
        }
        #expect(searched.map(\.path) == ["/nonexistent/makemkvcon", "/nonexistent/bin/makemkvcon"])
    }

    @Test func ripRefusesATitleFromAnotherScan() async throws {
        let scan = Scan(
            source: .disc(0),
            settings: ScanSettings(),
            result: DiscScan(parsing: "TCOUNT:1\nTINFO:0,16,0,\"00001.mpls\"\nTINFO:0,27,0,\"a_t00.mkv\"")
        )
        let foreign = Title(index: 0, attributes: [.sourceFileName: Attribute(id: .sourceFileName, messageCode: 0, value: "00002.mpls")], tracks: [])
        let makeMKV = MakeMKV(executable: URL(fileURLWithPath: "/nonexistent/makemkvcon"))
        let error = try await #require(throws: MakeMKVError.self) {
            try await makeMKV.rip(foreign, from: scan, to: FileManager.default.temporaryDirectory)
        }
        guard case .titleNotInScan(let index) = error else {
            Issue.record("unexpected \(error)")
            return
        }
        #expect(index == 0)
    }

    @Test func ripRefusesATitleWithNoOutputName() async throws {
        let scan = Scan(source: .disc(0), settings: ScanSettings(), result: DiscScan(parsing: "TCOUNT:1\nTINFO:0,16,0,\"00001.mpls\""))
        let makeMKV = MakeMKV(executable: URL(fileURLWithPath: "/nonexistent/makemkvcon"))
        let error = try await #require(throws: MakeMKVError.self) {
            try await makeMKV.rip(scan.titles[0], from: scan, to: FileManager.default.temporaryDirectory)
        }
        guard case .titleHasNoOutputName(let index) = error else {
            Issue.record("unexpected \(error)")
            return
        }
        #expect(index == 0)
    }
}
