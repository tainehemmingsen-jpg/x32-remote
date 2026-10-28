import XCTest
@testable import X32Core

final class SceneFileTests: XCTestCase {
    private let sample = """
    #4.0# "Sunday AM" "worship" %000000000 1 X32-Edit 4.0

    /config/chlink OFF OFF ON OFF OFF OFF OFF OFF OFF OFF OFF OFF OFF OFF OFF OFF
    /ch/01/config "Kick" 1 RD 1
    /ch/01/mix ON -6.0 ON +0 OFF -oo
    /ch/02/config "Snare \\"top\\"" 1 RD 2
    /bus/01/config "Vox Wedge" 1 MG 0
    /fx/1 HALL
    /config/routing/IN 1 2 3 4 5
    /outputs/main/01 4 2
    /headamp/000 +30.0 ON
    """

    func testParsesHeaderAndLines() {
        let scene = SceneFile.parse(sample, fallbackName: "x")!
        XCTAssertEqual(scene.name, "Sunday AM")
        XCTAssertEqual(scene.note, "worship")
        XCTAssertEqual(scene.lines.count, 9)
        XCTAssertEqual(scene.channelNames, ["Kick", "Snare \"top\""])
    }

    func testNotASceneFile() {
        XCTAssertNil(SceneFile.parse("hello\nworld", fallbackName: "x"))
    }

    func testFallbackName() {
        XCTAssertEqual(SceneFile.parse("/ch/01/config \"A\" 1 RD 1", fallbackName: "MyFile")?.name, "MyFile")
    }

    func testPartsFilterLines() {
        let scene = SceneFile.parse(sample, fallbackName: "x")!
        let safe = scene.lines(including: Set(SceneFile.Part.allCases.filter(\.onByDefault)))
        XCTAssertFalse(safe.contains { $0.hasPrefix("/headamp/") }, "preamps are off by default")
        XCTAssertTrue(safe.contains { $0.hasPrefix("/fx/1") })
        let channelsOnly = scene.lines(including: [.channels])
        XCTAssertEqual(channelsOnly.count, 3)
        XCTAssertEqual(scene.lines(including: [.routing]).count, 2)
        XCTAssertEqual(scene.lines(including: [.buses]).count, 2)   // chlink + bus config
    }

    func testRoundTrip() {
        let scene = SceneFile.parse(sample, fallbackName: "x")!
        let again = SceneFile.parse(scene.text(), fallbackName: "y")!
        XCTAssertEqual(again.name, scene.name)
        XCTAssertEqual(again.lines, scene.lines)
        XCTAssertTrue(scene.text().hasPrefix("#4.0# \"Sunday AM\""))
        XCTAssertTrue(scene.text(firmware: "2.12").hasPrefix("#2.7#"))
    }

    func testBasicChanges() {
        let c = SceneFile.basicChanges("/ch/01/config \"Kick\" 1 RD 1")
        XCTAssertEqual(c.first?.0, "/ch/01/config/name")
        XCTAssertEqual(c.first?.1, .string("Kick"))
        XCTAssertEqual(c.last?.1, .int(1))
        let m = SceneFile.basicChanges("/ch/01/mix OFF -10.0 ON +0 OFF -oo")
        XCTAssertEqual(m[0].1, .int(0))
        XCTAssertEqual(m[1].1.floatValue ?? 0, 0.5, accuracy: 0.001)
        let d = SceneFile.basicChanges("/dca/3 ON -oo")
        XCTAssertEqual(d[0].0, "/dca/3/on")
        XCTAssertEqual(d[1].1, .float(0))
    }

    func testConfigLineRoundTrips() {
        let line = SceneFile.configLine("/ch/05/config", name: "Lead Vox", color: 5, source: 5)
        XCTAssertEqual(line, "/ch/05/config \"Lead Vox\" 1 MG 5")
        XCTAssertEqual(SceneFile.basicChanges(line).map(\.0), ["/ch/05/config/name", "/ch/05/config/color"])
    }

    func testNodeList() {
        XCTAssertEqual(SceneNodes.all.count, 2103)
        XCTAssertTrue(SceneNodes.all.contains("/ch/32/eq/4"))
        XCTAssertEqual(SceneFile.nodeRequest("/ch/01/config"), "ch/01/config")
        XCTAssertEqual(Set(SceneNodes.all).count, SceneNodes.all.count)
    }

    func testLibraryStorage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID()).json")
        let scene = SceneFile.parse(sample, fallbackName: "x")!
        SceneLibrary.save([scene], to: url)
        XCTAssertEqual(SceneLibrary.load(from: url), [scene])
        try? FileManager.default.removeItem(at: url)
    }
}

final class SceneBuilderTests: XCTestCase {
    private func names(_ text: String) -> [String] {
        SceneBuilder.plan(from: text)?.inputs.map(\.name) ?? []
    }

    func testBandList() {
        let plan = SceneBuilder.plan(from: "rock band: 2 vox, acoustic, electric guitar, bass, keys, drums")!
        let n = plan.inputs.map(\.name)
        XCTAssertEqual(Array(n.prefix(7)), ["Kick", "Snare", "Hi-Hat", "Rack Tom", "Floor Tom", "OH L", "OH R"])
        XCTAssertTrue(n.contains("Bass"))
        XCTAssertTrue(n.contains("Acoustic"))
        XCTAssertTrue(n.contains("Gtr"))
        XCTAssertTrue(n.contains("Keys L") && n.contains("Keys R"))
        XCTAssertTrue(n.contains("Lead Vox") && n.contains("BV 1"))
        XCTAssertEqual(plan.inputs.first { $0.name == "Kick" }?.starter, "Kick")
        XCTAssertEqual(plan.dcas, ["Drums", "Band", "Vocals"])
    }

    func testChurchEventDefaults() {
        let plan = SceneBuilder.plan(from: "Sunday church service")!
        XCTAssertTrue(plan.inputs.contains { $0.name == "Pastor" && $0.starter == "Lapel mic" })
        XCTAssertFalse(plan.mixes.isEmpty)
    }

    func testListedInputsWinOverEventDefaults() {
        let n = names("church service with pastor lapel mic, worship leader, acoustic and playback")
        XCTAssertEqual(n, ["Acoustic", "Lead Vox", "Pastor", "Playback L", "Playback R"])
    }

    func testCounts() {
        XCTAssertEqual(names("3 bvs").filter { $0.hasPrefix("BV") }.count, 3)
        XCTAssertEqual(names("two acoustic guitars"), ["Acoustic 1", "Acoustic 2"])
        XCTAssertEqual(names("4 handhelds"), ["Mic 1", "Mic 2", "Mic 3", "Mic 4"])
    }

    func testGymClass() {
        let n = names("spin class")
        XCTAssertEqual(n, ["Instructor", "Mic", "Music L", "Music R"])
    }

    func testNothingRecognised() {
        XCTAssertNil(SceneBuilder.plan(from: "hello there"))
    }

    func testNamesFitTheDesk() {
        XCTAssertEqual(SceneBuilder.deskName("A very long channel name"), "A very long ")
        for s in StarterPresets.all { XCTAssertNotNil(StarterPresets.named(s.name)) }
    }

    func testMonitorMixesWhenAskedFor() {
        let plan = SceneBuilder.plan(from: "lead vocal, 2 bvs, guitar, bass, drums with wedges")!
        XCTAssertEqual(plan.mixes, ["Drums", "Bass", "Gtr", "Lead Vox", "BVs"])
    }

    func testChangesCoverNamesStartersDCAsAndBuses() {
        let plan = SceneBuilder.plan(from: "kick, snare, lead vocal, keys with wedges")!
        let changes = SceneBuilder.changes(for: plan, clearRest: true)
        let dict = Dictionary(changes.map { ($0.0, $0.1) }, uniquingKeysWith: { _, b in b })
        XCTAssertEqual(dict["/ch/01/config/name"], .string("Kick"))
        XCTAssertEqual(dict["/ch/01/config/color"], .int(1))
        XCTAssertEqual(dict["/ch/01/grp/dca"], .int(1))          // Drums = DCA 1
        XCTAssertEqual(dict["/ch/05/grp/dca"], .int(4))          // Vocals = DCA 3
        XCTAssertNotNil(dict["/ch/01/eq/1/f"])
        XCTAssertEqual(dict["/ch/03/mix/pan"], .float(0))        // Keys L
        XCTAssertEqual(dict["/ch/04/mix/pan"], .float(1))        // Keys R
        XCTAssertEqual(dict["/ch/32/config/name"], .string(""))  // the rest cleared
        XCTAssertEqual(dict["/dca/1/config/name"], .string("Drums"))
        XCTAssertNotNil(dict["/bus/01/config/name"])
        for (_, v) in changes { if case .float(let f) = v { XCTAssertTrue(f >= 0 && f <= 1) } }
    }
}
