import XCTest
@testable import X32Core

final class SnapshotTests: XCTestCase {
    private typealias P = Snapshot.ParamType

    /// A fake desk: every snapshot address answers, with a value derived from `seed`.
    private func desk(_ seed: Float, headamp: Int = 0) -> [String: OSCArg] {
        var d: [String: OSCArg] = [:]
        for a in Snapshot.allAddresses() {
            if a.hasPrefix("/-ha/") {
                // Channel n is fed by headamp n-1 + offset, aux by 32+.
                let n = Int(a.dropFirst(5).prefix(2))!
                d[a] = .int(Int32((n + headamp) % 128))
            } else if a.hasSuffix("/name") {
                d[a] = .string("N\(seed)")
            } else if a.hasSuffix("/on") || a.hasSuffix("/color") || a.hasSuffix("/mode") {
                d[a] = .int(Int32(seed))
            } else {
                d[a] = .float(seed / 10)
            }
        }
        for ha in 0..<128 {
            d[StripID.headampGainPath(ha)] = .float(seed / 10)
            d[StripID.headampPhantomPath(ha)] = .int(Int32(seed))
        }
        return d
    }

    private func changed(_ c: [(String, OSCArg)]) -> Set<String> { Set(c.map(\.0)) }

    // MARK: Addresses

    func testAddressCoveragePerStripKind() {
        let dca = StripID(.dca, 3)
        XCTAssertEqual(Snapshot.addresses(for: dca, type: .fader), ["/dca/3/fader"])
        XCTAssertEqual(Snapshot.addresses(for: dca, type: .mute), ["/dca/3/on"])
        XCTAssertEqual(Snapshot.addresses(for: dca, type: .names), ["/dca/3/config/name", "/dca/3/config/color"])
        for t in [P.pan, .sends, .eq, .gate, .dyn, .preamp, .groups] {
            XCTAssertEqual(Snapshot.addresses(for: dca, type: t), [], "DCA has no \(t)")
        }

        let ch = StripID(.channel, 5)
        XCTAssertEqual(Snapshot.addresses(for: ch, type: .fader), ["/ch/05/mix/fader"])
        XCTAssertEqual(Snapshot.addresses(for: ch, type: .eq).count, 1 + 4 * 4)
        XCTAssertTrue(Snapshot.addresses(for: ch, type: .gate).contains("/ch/05/gate/thr"))
        XCTAssertTrue(Snapshot.addresses(for: ch, type: .dyn).contains("/ch/05/dyn/keysrc"))
        let sends = Snapshot.addresses(for: ch, type: .sends)
        XCTAssertEqual(sends.count, 16 * 2 + 8)
        XCTAssertTrue(sends.contains("/ch/05/mix/16/level"))
        XCTAssertTrue(sends.contains("/ch/05/mix/15/pan"))
        XCTAssertFalse(sends.contains("/ch/05/mix/16/pan"))
        XCTAssertEqual(Snapshot.addresses(for: ch, type: .preamp),
                       ["/ch/05/preamp/trim", "/ch/05/preamp/invert", "/ch/05/preamp/hpon", "/ch/05/preamp/hpf", "/ch/05/preamp/hpslope"])
        XCTAssertEqual(Snapshot.addresses(for: ch, type: .preamp, headamp: 4).suffix(2), ["/headamp/004/gain", "/headamp/004/phantom"])
        XCTAssertEqual(Snapshot.addresses(for: ch, type: .groups), ["/ch/05/grp/dca", "/ch/05/grp/mute"])

        let mtx = StripID(.matrix, 2)
        XCTAssertEqual(Snapshot.addresses(for: mtx, type: .sends), [], "matrices have no sends")
        XCTAssertEqual(Snapshot.addresses(for: mtx, type: .pan), [])
        XCTAssertEqual(Snapshot.addresses(for: mtx, type: .gate), [])
        XCTAssertEqual(Snapshot.addresses(for: mtx, type: .groups), [])
        XCTAssertEqual(Snapshot.addresses(for: mtx, type: .eq).count, 1 + 6 * 4)
        XCTAssertEqual(Snapshot.addresses(for: mtx, type: .preamp), ["/mtx/02/preamp/invert"])

        let lr = StripID.mainLR
        let lrSends = Snapshot.addresses(for: lr, type: .sends)
        XCTAssertEqual(lrSends.first, "/main/st/mix/01/level", "main LR sends feed the matrices")
        XCTAssertEqual(lrSends.filter { $0.hasSuffix("/level") }.count, 6)
        XCTAssertEqual(Snapshot.addresses(for: lr, type: .pan), ["/main/st/mix/pan"])
        XCTAssertEqual(Snapshot.addresses(for: StripID.monoC, type: .pan), [])
        XCTAssertEqual(Snapshot.addresses(for: StripID.bus(1), type: .groups), ["/bus/01/grp/dca", "/bus/01/grp/mute"])
        XCTAssertEqual(Snapshot.addresses(for: StripID.bus(1), type: .preamp), [])
        XCTAssertEqual(Snapshot.addresses(for: StripID(.fxReturn, 1), type: .gate), [])
        XCTAssertEqual(Snapshot.addresses(for: StripID(.auxIn, 1), type: .preamp, headamp: 32),
                       ["/auxin/01/preamp/trim", "/auxin/01/preamp/invert", "/headamp/032/gain", "/headamp/032/phantom"])
        XCTAssertEqual(Snapshot.addresses(for: StripID.bus(1), type: .preamp, headamp: 3), [], "no headamp on a bus")
    }

    func testAllAddresses() {
        let all = Snapshot.allAddresses()
        XCTAssertEqual(all.count, Set(all).count, "no duplicates")
        XCTAssertTrue(all.contains("/ch/01/mix/fader"))
        XCTAssertTrue(all.contains("/dca/8/config/name"))
        XCTAssertTrue(all.contains("/-ha/00/index"))
        XCTAssertTrue(all.contains("/-ha/39/index"))
        XCTAssertFalse(all.contains { $0.hasPrefix("/headamp/") })
        XCTAssertFalse(all.contains { $0.hasPrefix("/dca/") && $0.contains("/eq") })
        let withHA = Snapshot.allAddresses { $0.kind == .channel ? $0.index - 1 : nil }
        XCTAssertTrue(withHA.contains("/headamp/000/gain"))
        XCTAssertTrue(withHA.contains("/headamp/031/phantom"))
        XCTAssertEqual(withHA.count, Set(withHA).count)
    }

    // MARK: Capture

    func testCaptureStoresEverythingIncludingOutOfScope() {
        let d = desk(5)
        let s = Snapshot.capture(name: "Song", value: { d[$0] })
        XCTAssertEqual(s.scope, RecallScope())
        XCTAssertFalse(s.scope.types.contains(.preamp))
        XCTAssertFalse(s.scope.types.contains(.names))
        XCTAssertEqual(s.values["/ch/01/config/name"], .string("N5.0"), "names captured even though not recalled")
        XCTAssertEqual(s.values["/ch/03/preamp/trim"], .float(0.5))
        XCTAssertEqual(s.headamps["channel-3"], 2)
        XCTAssertEqual(s.values["/headamp/002/gain"], .float(0.5))
        XCTAssertNil(s.values["/-ha/02/index"], "the headamp patch itself is not recalled")
        XCTAssertEqual(s.values.count, Set(Snapshot.allAddresses { Snapshot.headamp(of: $0, value: { d[$0] }) }).count - 40)
    }

    func testCaptureSkipsUnknownValues() {
        let s = Snapshot.capture(name: "Empty", value: { $0 == "/ch/01/mix/fader" ? .float(0.75) : nil })
        XCTAssertEqual(s.values, ["/ch/01/mix/fader": .float(0.75)])
    }

    // MARK: Recall

    func testUnchangedValuesAreSkipped() {
        let d = desk(5)
        let s = Snapshot.capture(name: "A", value: { d[$0] })
        XCTAssertTrue(s.changes(current: { d[$0] }).isEmpty)
        var now = d
        now["/ch/02/mix/fader"] = .float(0.1)
        now["/ch/02/eq/1/g"] = .float(0.9)
        XCTAssertEqual(changed(s.changes(current: { now[$0] })), ["/ch/02/mix/fader", "/ch/02/eq/1/g"])
    }

    func testUnknownCurrentValueIsSent() {
        let s = Snapshot(name: "A", values: ["/ch/01/mix/on": .int(1)])
        XCTAssertEqual(s.changes(current: { _ in nil }).map(\.0), ["/ch/01/mix/on"])
    }

    func testScopeFiltersStripsAndTypes() {
        let target = desk(5)
        let now = desk(2)
        var s = Snapshot.capture(name: "A", value: { target[$0] })
        s.scope = RecallScope(strips: [StripID.channel(1), StripID(.dca, 2)], types: [.fader, .mute])
        XCTAssertEqual(changed(s.changes(current: { now[$0] })), ["/ch/01/mix/fader", "/ch/01/mix/on", "/dca/2/fader", "/dca/2/on"])

        // An explicit effective scope overrides the stored one.
        let eq = s.changes(scope: RecallScope(strips: [StripID.bus(4)], types: [.eq]), current: { now[$0] })
        XCTAssertEqual(eq.count, 1 + 6 * 4)
        XCTAssertTrue(eq.allSatisfy { $0.0.hasPrefix("/bus/04/eq") })

        // The default scope recalls no preamps or names.
        let d = Snapshot.capture(name: "B", value: { target[$0] }).changes(current: { now[$0] })
        XCTAssertFalse(d.contains { $0.0.contains("/preamp/") || $0.0.hasPrefix("/headamp/") || $0.0.hasSuffix("/config/name") })
        XCTAssertTrue(d.contains { $0.0 == "/ch/01/gate/thr" })
    }

    func testFadersComeLast() {
        let target = desk(5)
        let now = desk(2)
        let c = Snapshot.capture(name: "A", value: { target[$0] }).changes(current: { now[$0] })
        let firstFader = c.firstIndex { $0.0.hasSuffix("/fader") }!
        XCTAssertTrue(c[firstFader...].allSatisfy { $0.0.hasSuffix("/fader") }, "nothing after the faders")
        XCTAssertEqual(c.filter { $0.0.hasSuffix("/fader") }.count, StripID.everything.count)
        XCTAssertGreaterThan(firstFader, 0)
    }

    func testRecallSafes() {
        let target = desk(5)
        let now = desk(2)
        let s = Snapshot.capture(name: "A", scope: .everything, value: { target[$0] })
        let lectern = StripID.channel(20)
        var safes = RecallSafes(strips: [lectern], types: [.preamp])
        safes.setSafe(StripID.channel(3), .eq, true)
        let c = changed(s.changes(safes: safes, current: { now[$0] }))
        XCTAssertFalse(c.contains { $0.hasPrefix("/ch/20/") }, "safe strip untouched")
        XCTAssertFalse(c.contains { $0.contains("/preamp/") || $0.hasPrefix("/headamp/") }, "all preamps safe")
        XCTAssertFalse(c.contains { $0.hasPrefix("/ch/03/eq") })
        XCTAssertTrue(c.contains("/ch/03/mix/fader"))
        XCTAssertTrue(c.contains("/ch/04/eq/1/g"))
        XCTAssertTrue(safes.isSafe(StripID.channel(3), .eq))
        safes.setSafe(StripID.channel(3), .eq, false)
        XCTAssertNil(safes.stripTypes["channel-3"])
        XCTAssertFalse(RecallSafes().hasSafe(lectern))
        XCTAssertTrue(safes.hasSafe(lectern))
    }

    func testHeadampGainFollowsTheChannelAndRespectsSafes() {
        let target = desk(5)
        let s = Snapshot.capture(name: "A", scope: .everything, value: { target[$0] })
        // Channel 1 has been repatched from headamp 0 to headamp 50 since.
        var now = desk(2)
        now["/-ha/00/index"] = .int(50)
        let c = Dictionary(s.changes(current: { now[$0] }), uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(c["/headamp/050/gain"], .float(0.5))
        XCTAssertEqual(c["/headamp/050/phantom"], .int(5))

        // Channel 2 (headamp 1) safe on preamp: another strip sharing headamp 1 must not change it.
        now["/-ha/05/index"] = .int(1)
        var safes = RecallSafes()
        safes.setSafe(StripID.channel(2), .preamp, true)
        let c2 = changed(s.changes(safes: safes, current: { now[$0] }))
        XCTAssertFalse(c2.contains("/headamp/001/gain"))
        XCTAssertTrue(c2.contains("/ch/06/preamp/trim"))
    }

    // MARK: Fades

    func testFadeIsLinearInDB() {
        // -30 dB (0.25) to 0 dB (0.75): halfway is -15 dB, not fader 0.5.
        let mid = SnapshotFade.value(from: 0.25, to: 0.75, elapsed: 1, duration: 2)
        XCTAssertEqual(X32Math.faderToDB(mid), -15, accuracy: 0.01)
        XCTAssertEqual(mid, X32Math.dbToFader(-15), accuracy: 0.0001)
        XCTAssertNotEqual(mid, 0.5, accuracy: 0.01)
        XCTAssertEqual(SnapshotFade.value(from: 0.5, to: 1, elapsed: 0.5, duration: 1), 0.75, accuracy: 0.0001)
        XCTAssertEqual(SnapshotFade.value(from: 0.25, to: 0.75, elapsed: 0, duration: 2), 0.25)
        XCTAssertEqual(SnapshotFade.value(from: 0.25, to: 0.75, elapsed: 3, duration: 2), 0.75)
        XCTAssertEqual(SnapshotFade.value(from: 0.25, to: 0.75, elapsed: 1, duration: 0), 0.75, "0 = snap")
        // From -inf the fade starts at the desk's -90 dB floor.
        XCTAssertEqual(X32Math.faderToDB(SnapshotFade.value(from: 0, to: 0.75, elapsed: 1, duration: 2)), -45, accuracy: 0.01)
    }

    func testRecallSplitsSnapsAndFades() {
        let target = desk(5)
        let now = desk(2)
        var s = Snapshot.capture(name: "A", value: { target[$0] })
        s.fadeTime = 3
        let r = s.recall(current: { now[$0] })
        XCTAssertEqual(r.duration, 3)
        XCTAssertTrue(r.fades.allSatisfy { SnapshotFade.isFadeable($0.address) })
        XCTAssertTrue(r.fades.contains { $0.address == "/ch/01/mix/fader" && $0.from == 0.2 && $0.to == 0.5 })
        XCTAssertTrue(r.fades.contains { $0.address == "/dca/1/fader" })
        XCTAssertTrue(r.fades.contains { $0.address == "/ch/01/mix/03/level" })
        XCTAssertFalse(r.snaps.contains { SnapshotFade.isFadeable($0.0) })
        XCTAssertTrue(r.snaps.contains { $0.0 == "/ch/01/mix/on" })
        XCTAssertFalse(SnapshotFade.isFadeable("/ch/01/mix/mlevel"))

        s.fadeTime = 0
        let snap = s.recall(current: { now[$0] })
        XCTAssertTrue(snap.fades.isEmpty)
        XCTAssertEqual(snap.snaps.count, s.changes(current: { now[$0] }).count)
    }

    func testFadeRunSendsOnlyChangesAndEndsOnTarget() {
        var run = SnapshotFade.Run(moves: [.init(address: "/ch/01/mix/fader", from: 0.25, to: 0.75),
                                           .init(address: "/ch/02/mix/fader", from: 0.5, to: 0.5)], duration: 1)
        let first = run.step(elapsed: 0.5)
        XCTAssertEqual(first.map(\.0), ["/ch/01/mix/fader"], "a fader that doesn't move isn't resent")
        XCTAssertTrue(run.step(elapsed: 0.5).isEmpty)
        let last = run.step(elapsed: 1.2)
        XCTAssertEqual(last.first?.1, .float(0.75))
        XCTAssertTrue(run.isFinished)
        XCTAssertTrue(run.step(elapsed: 2).isEmpty)
        XCTAssertTrue(SnapshotFade.Run(moves: [], duration: 1).isFinished)
    }

    // MARK: Show

    private func show(_ n: Int) -> SnapshotShow {
        SnapshotShow(name: "Gig", snapshots: (1...n).map { Snapshot(name: "S\($0)") })
    }

    func testNextAndPreviousAtTheEnds() {
        var s = show(3)
        XCTAssertNil(s.currentIndex)
        XCTAssertEqual(s.nextIndex, 0)
        XCTAssertNil(s.previousIndex)
        s.currentIndex = 0
        XCTAssertEqual(s.nextIndex, 1)
        XCTAssertNil(s.previousIndex)
        s.currentIndex = 2
        XCTAssertNil(s.nextIndex)
        XCTAssertEqual(s.previousIndex, 1)
        XCTAssertNil(SnapshotShow(name: "Empty").nextIndex)
        s.currentIndex = 9
        XCTAssertEqual(s.currentIndex, 2, "clamped")
    }

    func testInsertDuplicateDeleteMoveRename() {
        var s = show(3)
        s.currentIndex = 0
        XCTAssertEqual(s.insertAfterCurrent(Snapshot(name: "New")), 1)
        XCTAssertEqual(s.snapshots.map(\.name), ["S1", "New", "S2", "S3"])
        XCTAssertEqual(s.snapshots.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(s.currentIndex, 1)

        XCTAssertEqual(s.duplicate(at: 3), 4)
        XCTAssertEqual(s.snapshots.last?.name, "S3 copy")
        XCTAssertNotEqual(s.snapshots[3].id, s.snapshots[4].id)
        XCTAssertEqual(s.currentIndex, 4)

        s.currentIndex = 2   // S2
        s.move(from: 2, to: 0)
        XCTAssertEqual(s.snapshots.map(\.name), ["S2", "S1", "New", "S3", "S3 copy"])
        XCTAssertEqual(s.current?.name, "S2", "current follows the move")
        s.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(s.snapshots.map(\.name), ["S1", "New", "S2", "S3", "S3 copy"])
        XCTAssertEqual(s.current?.name, "S2")

        s.delete(at: 2)   // the current one
        XCTAssertEqual(s.current?.name, "New")
        XCTAssertEqual(s.snapshots[s.nextIndex!].name, "S3", "next still goes to what followed")
        s.delete(at: 0)
        XCTAssertEqual(s.current?.name, "New")
        s.rename(at: 0, to: "Walk-in")
        XCTAssertEqual(s[0].name, "Walk-in")
        XCTAssertEqual(s.snapshots.map(\.number), [1, 2, 3])

        var one = show(1)
        one.currentIndex = 0
        one.delete(at: 0)
        XCTAssertNil(one.currentIndex)
    }

    func testUpdateKeepsScopeNameAndFade() {
        var s = SnapshotShow(name: "Gig")
        let a = desk(5)
        var snap = Snapshot.capture(name: "Verse", fadeTime: 2.5, value: { a[$0] })
        snap.scope = RecallScope(strips: [StripID.channel(1)], types: [.fader])
        snap.notes = "Keys solo"
        s.insertAfterCurrent(snap)
        let b = desk(7)
        s.update(at: 0, value: { b[$0] })
        XCTAssertEqual(s[0].name, "Verse")
        XCTAssertEqual(s[0].fadeTime, 2.5)
        XCTAssertEqual(s[0].notes, "Keys solo")
        XCTAssertEqual(s[0].scope, snap.scope)
        XCTAssertEqual(s[0].id, snap.id)
        XCTAssertEqual(s[0].values["/ch/01/mix/fader"], .float(0.7))
        XCTAssertEqual(s[0].values["/bus/02/eq/1/g"], .float(0.7))
    }

    func testRecallUsesShowSafes() {
        let a = desk(5)
        let now = desk(2)
        var s = SnapshotShow(name: "Gig", safes: RecallSafes(types: [.fader]))
        s.insertAfterCurrent(Snapshot.capture(name: "A", value: { a[$0] }))
        let r = s.recall(at: 0, current: { now[$0] })!
        XCTAssertFalse(r.snaps.contains { $0.0.hasSuffix("/fader") })
        XCTAssertNil(s.recall(at: 5, current: { now[$0] }))
    }

    // MARK: Store

    func testStoreRoundTrip() {
        let d = UserDefaults(suiteName: "snapshots-test-\(UUID())")!
        let a = desk(5)
        var show = SnapshotShow(name: "Friday", safes: RecallSafes(strips: [StripID.channel(20)], types: [.preamp]))
        var snap = Snapshot.capture(name: "Walk-in", fadeTime: 4, value: { a[$0] })
        snap.scope = RecallScope(strips: [StripID.channel(1), StripID.mainLR], types: [.fader, .mute])
        show.insertAfterCurrent(snap)
        show.insertAfterCurrent(Snapshot(name: "Band", notes: "Loud"))
        SnapshotStore.save([show], d)
        let loaded = SnapshotStore.load(d)
        XCTAssertEqual(loaded, [show])
        XCTAssertEqual(loaded.first?.currentIndex, 1)
        XCTAssertEqual(loaded.first?[0].values["/ch/01/config/name"], .string("N5.0"))

        var second = SnapshotShow(name: "Sunday")
        second.append(Snapshot(name: "Service"))
        SnapshotStore.saveShow(second, d)
        show.rename(at: 1, to: "Band 2")
        SnapshotStore.saveShow(show, d)
        XCTAssertEqual(SnapshotStore.load(d).map(\.name), ["Friday", "Sunday"])
        XCTAssertEqual(SnapshotStore.loadShow(id: show.id, d)?[1].name, "Band 2")
        XCTAssertEqual(SnapshotStore.loadShow(d)?.name, "Friday")
        XCTAssertEqual(SnapshotStore.load(UserDefaults(suiteName: "snapshots-empty-\(UUID())")!), [])
    }

    func testStoreKeepsBackupOfUnreadableData() {
        let d = UserDefaults(suiteName: "snapshots-bad-\(UUID())")!
        d.set(Data("nonsense".utf8), forKey: SnapshotStore.key)
        XCTAssertEqual(SnapshotStore.load(d), [])
        XCTAssertNotNil(d.data(forKey: SnapshotStore.key + ".backup"))
    }

    func testOldSnapshotWithMissingFieldsDecodes() throws {
        let json = #"[{"name":"Old","snapshots":[{"name":"One","values":{"/ch/01/mix/on":{"i":1}}}]}]"#
        let shows = try XCTUnwrap(SnapshotStore.decode(Data(json.utf8)))
        XCTAssertEqual(shows.first?[0].name, "One")
        XCTAssertEqual(shows.first?[0].scope, RecallScope())
        XCTAssertEqual(shows.first?[0].values["/ch/01/mix/on"], .int(1))
        XCTAssertNil(shows.first?.currentIndex)
    }

    // MARK: Summary

    func testSummaries() {
        XCTAssertEqual(RecallScope().summary, "All strips · no preamps")
        XCTAssertEqual(RecallScope.everything.summary, "All strips · everything")
        let strips: Set<StripID> = Set((1...8).map { StripID.channel($0) } + [StripID.channel(12)])
        XCTAssertEqual(RecallScope(strips: strips, types: [.fader, .mute]).summary, "Ch 1–8, 12 · faders and mutes only")
        XCTAssertEqual(RecallScope(strips: [StripID.bus(1), StripID.bus(2), StripID.mainLR, StripID(.dca, 3)], types: [.eq]).summary,
                       "Bus 1–2, LR, DCA 3 · EQ only")
        XCTAssertEqual(RecallScope(types: Set(P.allCases).subtracting([.names])).summary, "All strips · all but names")
        XCTAssertEqual(RecallScope(types: Set(P.allCases).subtracting([.preamp, .eq, .names])).summary, "All strips · no EQ or preamps")
        XCTAssertEqual(RecallScope(types: Set(P.allCases).subtracting([.preamp])).summary, "All strips · no preamps, with names")
        XCTAssertEqual(RecallScope(strips: [], types: []).summary, "No strips · nothing")
        XCTAssertEqual(RecallScope(types: [.fader, .mute, .pan, .sends]).typeSummary, "faders, mutes, pan and sends")
        XCTAssertEqual(Snapshot(name: "X").summary, "All strips · no preamps")
    }
}
