// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import MakeMKV
import MakeMKVRobot
import XCTest

/// Everything here runs without a MakeMKV installation or a drive. The driver's process handling is
/// exercised against a real disc by hand; what can be checked offline is what it would ask for.
final class MakeMKVTests: XCTestCase {
    func testSourceArguments() {
        XCTAssertEqual(Source.disc(0).argument, "disc:0")
        XCTAssertEqual(Source.device("/dev/rdisk5").argument, "dev:/dev/rdisk5")
        XCTAssertEqual(Source.iso(URL(fileURLWithPath: "/tmp/a.iso")).argument, "iso:/tmp/a.iso")
        XCTAssertEqual(Source.folder(URL(fileURLWithPath: "/tmp/backup")).argument, "file:/tmp/backup")
    }

    func testScanSettingsArgumentsInFixedOrder() {
        XCTAssertEqual(ScanSettings().arguments, [])
        let settings = ScanSettings(
            minimumTitleLength: 0,
            cacheMegabytes: 1024,
            directIO: true,
            profile: URL(fileURLWithPath: "/tmp/p.mmcp.xml"),
            noScan: true,
            additionalArguments: ["--debug"]
        )
        XCTAssertEqual(settings.arguments, ["--minlength=0", "--cache=1024", "--directio=true", "--profile=/tmp/p.mmcp.xml", "--noscan", "--debug"])
    }

    func testLocateReportsWhereItLooked() {
        do {
            _ = try MakeMKV.locate(defaultLocations: [URL(fileURLWithPath: "/nonexistent/makemkvcon")], environment: ["PATH": "/nonexistent/bin"])
            XCTFail("expected a throw")
        } catch MakeMKVError.executableNotFound(let searched) {
            XCTAssertEqual(searched.map(\.path), ["/nonexistent/makemkvcon", "/nonexistent/bin/makemkvcon"])
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testRipRefusesATitleFromAnotherScan() async throws {
        let scan = Scan(
            source: .disc(0),
            settings: ScanSettings(),
            result: DiscScan(parsing: "TCOUNT:1\nTINFO:0,16,0,\"00001.mpls\"\nTINFO:0,27,0,\"a_t00.mkv\"")
        )
        let foreign = Title(index: 0, attributes: [.sourceFileName: Attribute(id: .sourceFileName, messageCode: 0, value: "00002.mpls")], tracks: [])
        let makeMKV = MakeMKV(executable: URL(fileURLWithPath: "/nonexistent/makemkvcon"))
        do {
            _ = try await makeMKV.rip(foreign, from: scan, to: FileManager.default.temporaryDirectory)
            XCTFail("expected a throw")
        } catch MakeMKVError.titleNotInScan(let index) {
            XCTAssertEqual(index, 0)
        }
    }

    func testRipRefusesATitleWithNoOutputName() async throws {
        let scan = Scan(source: .disc(0), settings: ScanSettings(), result: DiscScan(parsing: "TCOUNT:1\nTINFO:0,16,0,\"00001.mpls\""))
        let makeMKV = MakeMKV(executable: URL(fileURLWithPath: "/nonexistent/makemkvcon"))
        do {
            _ = try await makeMKV.rip(scan.titles[0], from: scan, to: FileManager.default.temporaryDirectory)
            XCTFail("expected a throw")
        } catch MakeMKVError.titleHasNoOutputName(let index) {
            XCTAssertEqual(index, 0)
        }
    }
}
