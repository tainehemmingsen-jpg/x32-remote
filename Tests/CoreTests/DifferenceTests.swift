import XCTest
@testable import X32Core

final class MixCheckTests: XCTestCase {
    private func channel(_ n: Int, _ name: String, peak: Float? = -20, fader: Float = 0, muted: Bool = false,
                         clipped: Bool = false, lowCut: Bool? = true, eq: [(Int, Float, Float)] = [],
                         gr: Float = 0) -> MixCheck.Channel {
        MixCheck.Channel(strip: StripID(.channel, n), name: name, muted: muted, faderDB: fader, recentPeak: peak,
                         clipped: clipped, lowCutOn: lowCut, eqOn: true, eq: eq.map { (type: $0.0, hz: $0.1, gain: $0.2) },
                         compOn: true, compReduction: gr, hasHeadamp: true)
    }

    private func ids(_ c: [MixCheck.Channel], main: Bool = false) -> [String] {
        MixCheck.issues(c, mainClipped: main).map(\.id)
    }

    func testHealthyChannelHasNoIssues() {
        XCTAssertEqual(ids([channel(1, "Kick")]), [])
    }

    func testClippingComesFirstWithAutoGain() {
        let issues = MixCheck.issues([channel(1, "Kick", lowCut: nil, gr: 18), channel(2, "Snare", clipped: true)], mainClipped: false)
        XCTAssertEqual(issues.first?.id, "clip-channel-2")
        XCTAssertEqual(issues.first?.fix, .autoGain)
    }

    func testQuietAndSilentAndUnused() {
        XCTAssertEqual(ids([channel(3, "Gtr", peak: -48)]), ["quiet-channel-3"])
        XCTAssertEqual(ids([channel(4, "Bass", peak: -90)]), ["silent-channel-4"])
        XCTAssertEqual(ids([channel(5, "", peak: -90, fader: -5)]), ["unused-channel-5"])
        XCTAssertEqual(ids([channel(5, "", peak: -90, fader: -5, muted: true)]), [])
        XCTAssertEqual(ids([channel(6, "Gtr", peak: nil)]), [], "nothing said until it has listened")
    }

    func testVoiceWithoutLowCutGetsAFix() {
        let issues = MixCheck.issues([channel(7, "Lead Vox", lowCut: false)], mainClipped: false)
        XCTAssertEqual(issues.map(\.id), ["lowcut-channel-7"])
        guard case .changes(let c, _)? = issues.first?.fix else { return XCTFail() }
        XCTAssertEqual(c["/ch/07/preamp/hpon"], .int(1))
        XCTAssertEqual(ids([channel(8, "Kick", lowCut: false)]), [], "not for a kick")
    }

    func testVoiceNames() {
        for v in ["Lead Vox", "BV 2", "Mic 1", "MC", "Pastor", "HH 2", "Bass Vox"] { XCTAssertTrue(MixCheck.isVoice(v), v) }
        for n in ["Bass Mic", "Gtr Amp Mic", "Kick", "Lead Gtr", "Tom Mic"] { XCTAssertFalse(MixCheck.isVoice(n), n) }
    }

    func testBigBoostAndSquash() {
        XCTAssertEqual(ids([channel(9, "Keys", eq: [(2, 3000, 12)])]), ["boost-channel-9"])
        XCTAssertEqual(ids([channel(9, "Keys", eq: [(0, 100, 12)])]), [], "a low cut's gain means nothing")
        XCTAssertEqual(ids([channel(10, "Vox", gr: 20)]), ["squash-channel-10"])
    }

    func testMainClip() {
        XCTAssertEqual(ids([], main: true), ["main-clip"])
    }

    func testPeakTracker() {
        var t = PeakTracker()
        let ch = StripID(.channel, 1)
        t.add(ch, -30, at: 0)
        XCTAssertNil(t.peak(ch, now: 1))
        t.add(ch, -10, at: 2)
        t.add(ch, -40, at: 6)
        XCTAssertEqual(t.peak(ch, now: 6), -10)
        t.add(ch, -50, at: 70)
        XCTAssertEqual(t.peak(ch, now: 70), -50, "older than a minute is forgotten")
    }
}

final class SceneDiffTests: XCTestCase {
    func testFindsChangesAndIgnoresFormatting() {
        let scene = ["/ch/01/config \"Kick\" 1 RD 1", "/ch/01/mix ON -6.0 ON +0 OFF -oo", "/ch/01/eq/2 PEQ 1k23 +3.00 2.0", "/fx/1 HALL"]
        let desk = ["/ch/01/config \"Kick\" 1 RD 1", "/ch/01/mix ON -10.0 ON 0 OFF -oo", "/ch/01/eq/2 PEQ 1k23 +3.0 2.0"]
        let c = SceneDiff.changes(scene: scene, desk: desk) { $0 == StripID(.channel, 1) ? "Kick" : "" }
        XCTAssertEqual(c.map(\.path), ["/ch/01/mix"])
        XCTAssertEqual(c[0].title, "Kick (Ch 1) · Fader, mute and pan")
        XCTAssertEqual(c[0].saved, "ON -6.0 ON +0 OFF -oo")
        XCTAssertEqual(c[0].now, "ON -10.0 ON 0 OFF -oo")
        XCTAssertEqual(c[0].restoreLine, scene[1])
    }

    func testTitles() {
        XCTAssertEqual(SceneDiff.title(for: "/ch/05/eq/2", names: { _ in "" }), "Ch 5 · EQ band 2")
        XCTAssertEqual(SceneDiff.title(for: "/bus/03/config", names: { _ in "Drums" }), "Drums (Mix 3) · Name, colour and source")
        XCTAssertEqual(SceneDiff.title(for: "/ch/02/mix/05", names: { _ in "" }), "Ch 2 · Send to Mix 5")
        XCTAssertEqual(SceneDiff.title(for: "/main/st/mix", names: { _ in "" }), "LR · Fader, mute and pan")
        XCTAssertEqual(SceneDiff.title(for: "/headamp/012", names: { _ in "" }), "Preamp 012 gain and 48V")
    }

    func testNumbers() {
        XCTAssertTrue(SceneDiff.same(["+0.0", "10k0"], ["0.0", "10000"]))
        XCTAssertFalse(SceneDiff.same(["ON"], ["OFF"]))
    }
}

final class SetlistTests: XCTestCase {
    func testDelayFollowsTempo() {
        XCTAssertEqual(SetlistMath.delayMS(bpm: 120), 500)
        XCTAssertEqual(SetlistMath.delayMS(bpm: 10), 3000)
        let song = Setlist.Song(name: "Song", bpm: 100)
        // Slot 3 holds a stereo delay (type 10), the others reverbs.
        let changes = SetlistMath.changes(for: song, previous: nil) { $0 == 3 ? 10 : 0 }
        XCTAssertEqual(changes.map(\.0), ["/fx/3/par/02"])
        XCTAssertEqual(Effects.delayTimeSpec.value(changes[0].1.floatValue ?? 0), 600, accuracy: 1)
    }

    func testSittingOutMutesAndUnmutes() {
        let a = Setlist.Song(name: "A", bpm: nil, sittingOut: ["channel-5", "channel-6"])
        let b = Setlist.Song(name: "B", bpm: nil, sittingOut: ["channel-6"])
        let c = SetlistMath.changes(for: b, previous: a) { _ in nil }
        XCTAssertTrue(c.contains { $0.0 == "/ch/06/mix/on" && $0.1 == .int(0) })
        XCTAssertTrue(c.contains { $0.0 == "/ch/05/mix/on" && $0.1 == .int(1) })
        XCTAssertEqual(c.count, 2)
    }

    func testTapTempo() {
        XCTAssertEqual(SetlistMath.bpm(fromTaps: [0, 0.5, 1.0, 1.5]), 120)
        XCTAssertNil(SetlistMath.bpm(fromTaps: [0]))
        XCTAssertEqual(SetlistMath.bpm(fromTaps: [0, 10, 10.5, 11]), 120, "a long pause is ignored")
    }

    func testStore() {
        let d = UserDefaults(suiteName: "setlist-test-\(UUID())")!
        let list = Setlist(name: "Friday", songs: [.init(name: "One", bpm: 98)])
        SetlistStore.save([list], d)
        XCTAssertEqual(SetlistStore.load(d), [list])
    }
}

final class DuckTests: XCTestCase {
    func testDuckingSetsTheMusicGates() {
        let duck = DuckSetup(mic: StripID(.channel, 22), music: [StripID(.channel, 31), StripID(.channel, 32)], depth: 12)
        let on = Dictionary(duck.changes(on: true).map { ($0.0, $0.1) }, uniquingKeysWith: { _, b in b })
        XCTAssertEqual(on["/ch/31/gate/mode"], .int(4))
        XCTAssertEqual(on["/ch/32/gate/keysrc"], .int(22))
        XCTAssertEqual(Specs.gateRange.value(on["/ch/31/gate/range"]?.floatValue ?? 0), 12, accuracy: 0.6)
        XCTAssertTrue(duck.isOn { on[$0] })
        let off = duck.changes(on: false)
        XCTAssertEqual(off.map(\.0), ["/ch/31/gate/on", "/ch/32/gate/on"])
        XCTAssertFalse(duck.isOn { _ in nil })
    }

    func testAuxMusicCantDuck() {
        let duck = DuckSetup(mic: StripID(.channel, 1), music: [StripID(.auxIn, 1)])
        XCTAssertTrue(duck.changes(on: true).isEmpty)
    }
}

final class InputListTests: XCTestCase {
    func testRiderInputList() {
        let text = """
        1. Kick In\tBeta 91
        2 Snare Top - SM57
        3) Hi-Hat
        5 Bass DI
        6\tVox 1\tSM58
        7 Tracks L
        """
        let plan = SceneBuilder.inputList(from: text)!
        XCTAssertEqual(plan.inputs.map(\.name), ["Kick In", "Snare Top", "Hi-Hat", "", "Bass DI", "Vox 1", "Tracks L"])
        XCTAssertEqual(plan.inputs[0].starter, "Kick")
        XCTAssertEqual(plan.inputs[4].starter, "Bass DI")
        XCTAssertEqual(plan.inputs[5].starter, "Lead vocal")
        XCTAssertEqual(plan.inputs[6].starter, "Playback")
        let changes = Dictionary(SceneBuilder.changes(for: plan, clearRest: false).map { ($0.0, $0.1) }, uniquingKeysWith: { _, b in b })
        XCTAssertEqual(changes["/ch/04/config/name"], .string(""))
        XCTAssertEqual(changes["/ch/04/config/color"], .int(0))
    }

    func testNotAList() {
        XCTAssertNil(SceneBuilder.inputList(from: "rock band with 2 vox"))
    }
}
