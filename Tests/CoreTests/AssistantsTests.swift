import XCTest
@testable import X32Core

final class FeedbackDetectorTests: XCTestCase {
    /// A noisy, roughly flat spectrum around -50 dB.
    private func music(_ frame: Int) -> [Float] {
        (0..<RTA.bandCount).map { i in -50 + 4 * sinf(Float(frame) * 1.7 + Float(i) * 0.9) }
    }

    func testSustainedNarrowPeakIsFound() {
        var d = FeedbackDetector()
        for f in 0..<10 {
            var frame = music(f)
            frame[72] = -20
            d.ingest(frame)
        }
        XCTAssertEqual(d.candidates.map(\.band), [72])
        XCTAssertTrue(d.candidates[0].live)
        XCTAssertGreaterThan(d.candidates[0].prominence, 20)
    }

    func testShortBurstIsIgnored() {
        var d = FeedbackDetector()
        for f in 0..<10 {
            var frame = music(f)
            if f == 4 || f == 5 { frame[40] = -15 }
            d.ingest(frame)
        }
        XCTAssertTrue(d.candidates.isEmpty)
    }

    func testBroadBumpIsNotFeedback() {
        var d = FeedbackDetector()
        for f in 0..<10 {
            // A wide resonance (like a boomy room), not a single ringing band.
            let frame = (0..<RTA.bandCount).map { i -> Float in -50 + 20 * expf(-powf(Float(i - 50) / 8, 2)) }
            d.ingest(frame.enumerated().map { $0.element + 0.5 * sinf(Float(f + $0.offset)) })
        }
        XCTAssertTrue(d.candidates.isEmpty)
    }

    func testWobblingPeakStaysOneCandidate() {
        var d = FeedbackDetector()
        for f in 0..<12 {
            var frame = music(f)
            frame[f % 2 == 0 ? 60 : 61] = -18
            d.ingest(frame)
        }
        XCTAssertEqual(d.candidates.count, 1)
    }

    func testStoppedPeakIsKeptButNotLive() {
        var d = FeedbackDetector()
        for f in 0..<10 {
            var frame = music(f)
            frame[30] = -20
            d.ingest(frame)
        }
        d.ingest(music(11))
        XCTAssertEqual(d.candidates.count, 1)
        XCTAssertFalse(d.candidates[0].live)
        d.dismiss(30)
        XCTAssertTrue(d.candidates.isEmpty)
    }
}

final class RingOutTests: XCTestCase {
    private let bus = StripID(.bus, 3)

    /// A flat 6-band bus EQ with a low cut on band 1 and a high cut on band 6.
    private func flatEQ() -> [String: OSCArg] {
        var v: [String: OSCArg] = [bus.eqOnPath: .int(1)]
        for b in 1...6 {
            v[bus.eqPath(b, "type")] = .int(b == 1 ? 0 : (b == 6 ? 5 : 2))
            v[bus.eqPath(b, "f")] = .float(0.5)
            v[bus.eqPath(b, "g")] = .float(0.5)
            v[bus.eqPath(b, "q")] = .float(0.5)
        }
        return v
    }

    func testFirstCutUsesAnInnerFlatBand() {
        let v = flatEQ()
        guard case .changes(let changes, _) = RingOut.notch(bus, frequency: 2500, value: { v[$0] }) else {
            return XCTFail("expected changes")
        }
        let paths = Dictionary(uniqueKeysWithValues: changes.map { ($0.0, $0.1) })
        XCTAssertEqual(paths[bus.eqPath(2, "type")], .int(2))
        let g = Specs.eqGain.value(paths[bus.eqPath(2, "g")]?.floatValue ?? 0)
        XCTAssertEqual(g, -6, accuracy: 0.3)
        let f = Specs.eqFreq.value(paths[bus.eqPath(2, "f")]?.floatValue ?? 0)
        XCTAssertEqual(f, 2500, accuracy: 100)
        XCTAssertGreaterThanOrEqual(Specs.eqQ.value(paths[bus.eqPath(2, "q")]?.floatValue ?? 0.5), 6)
        // The low and high cut bands are never touched.
        XCTAssertNil(paths[bus.eqPath(1, "type")])
        XCTAssertNil(paths[bus.eqPath(6, "type")])
    }

    func testSecondTapDeepensTheSameNotch() {
        var v = flatEQ()
        guard case .changes(let first, _) = RingOut.notch(bus, frequency: 2500, value: { v[$0] }) else { return XCTFail() }
        for (a, x) in first { v[a] = x }
        guard case .changes(let second, _) = RingOut.notch(bus, frequency: 2550, value: { v[$0] }) else { return XCTFail() }
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].0, bus.eqPath(2, "g"))
        XCTAssertEqual(Specs.eqGain.value(second[0].1.floatValue ?? 0), -9, accuracy: 0.3)
    }

    func testDifferentFrequencyTakesTheNextBand() {
        var v = flatEQ()
        guard case .changes(let first, _) = RingOut.notch(bus, frequency: 2500, value: { v[$0] }) else { return XCTFail() }
        for (a, x) in first { v[a] = x }
        guard case .changes(let second, _) = RingOut.notch(bus, frequency: 400, value: { v[$0] }) else { return XCTFail() }
        XCTAssertTrue(second.contains { $0.0 == bus.eqPath(3, "g") })
    }

    func testBoostedBandsAreLeftAlone() {
        var v = flatEQ()
        for b in 2...5 { v[bus.eqPath(b, "g")] = .float(0.6) }   // all +3 dB
        XCTAssertEqual(RingOut.notch(bus, frequency: 1000, value: { v[$0] }), .noFreeBand)
    }

    func testUnknownEQIsReadFirst() {
        guard case .unknown(let missing) = RingOut.notch(bus, frequency: 1000, value: { _ in nil }) else { return XCTFail() }
        XCTAssertTrue(missing.contains(bus.eqPath(1, "type")))
    }

    func testEQIsSwitchedOnIfItWasOff() {
        var v = flatEQ()
        v[bus.eqOnPath] = .int(0)
        guard case .changes(let changes, _) = RingOut.notch(bus, frequency: 800, value: { v[$0] }) else { return XCTFail() }
        XCTAssertTrue(changes.contains { $0.0 == bus.eqOnPath && $0.1 == .int(1) })
    }

    func testNotchesAreListed() {
        var v = flatEQ()
        guard case .changes(let first, _) = RingOut.notch(bus, frequency: 3000, value: { v[$0] }) else { return XCTFail() }
        for (a, x) in first { v[a] = x }
        let list = RingOut.notches(bus, value: { v[$0] })
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].band, 2)
    }
}

final class GainWizardTests: XCTestCase {
    func testQuietInputGetsMoreGain() {
        XCTAssertEqual(GainWizard.suggestion(currentGain: 20, peak: -30), .set(gain: 38, clipped: false))
    }

    func testLoudInputGetsLess() {
        XCTAssertEqual(GainWizard.suggestion(currentGain: 40, peak: -4), .set(gain: 32, clipped: false))
    }

    func testClippingTakesOffExtra() {
        XCTAssertEqual(GainWizard.suggestion(currentGain: 40, peak: 0), .set(gain: 22, clipped: true))
    }

    func testSilenceIsReported() {
        XCTAssertEqual(GainWizard.suggestion(currentGain: 20, peak: -90), .silent)
    }

    func testStaysInTheDesksRange() {
        XCTAssertEqual(GainWizard.suggestion(currentGain: 55, peak: -60), .set(gain: 60, clipped: false))
        XCTAssertEqual(GainWizard.suggestion(currentGain: -10, peak: 0), .set(gain: -12, clipped: true))
    }
}

final class StarterPresetTests: XCTestCase {
    func testEveryStarterLoadsOntoAChannel() {
        let ch = StripID(.channel, 7)
        for s in StarterPresets.all {
            let changes = StarterPresets.preset(s).clip.changes(onto: ch)
            let paths = Set(changes.map(\.0))
            XCTAssertTrue(paths.contains("/ch/07/preamp/hpf"), s.name)
            XCTAssertTrue(paths.contains("/ch/07/eq/4/type"), s.name)
            XCTAssertTrue(paths.contains("/ch/07/dyn/on"), s.name)
            // Gain and sends are never part of a starting point.
            XCTAssertFalse(paths.contains { $0.contains("/mix/") || $0.contains("headamp") }, s.name)
            for (_, v) in changes {
                if case .float(let f) = v { XCTAssertTrue(f >= 0 && f <= 1, s.name) }
            }
        }
    }

    func testVocalStarterValues() {
        let vocal = StarterPresets.all.first { $0.name == "Lead vocal" }!
        let v = StarterPresets.preset(vocal).clip.values
        XCTAssertEqual(Specs.hpf.value(v["/preamp/hpf"]!.floatValue!), 100, accuracy: 3)
        XCTAssertEqual(v["/dyn/ratio"], .int(6))   // 4:1
        XCTAssertEqual(v["/gate/on"], .int(0))
    }
}
