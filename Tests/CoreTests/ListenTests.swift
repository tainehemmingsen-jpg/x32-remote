import XCTest
@testable import X32Core

final class ListenProtocolTests: XCTestCase {
    func testRoundTrip() {
        let audio = ListenProtocol.Audio(channels: 2, sequence: 0xFFFF_FFFE, sampleRate: 48000, samples: [0, 1, -1, 32767, -32767, 100])
        let messages: [ListenProtocol.Message] = [.probe, .hello, .bye, .info(name: "Taine’s MacBook"), .audio(audio)]
        for m in messages {
            XCTAssertEqual(ListenProtocol.decode(ListenProtocol.encode(m)), m)
        }
    }

    func testRejectsJunk() {
        XCTAssertNil(ListenProtocol.decode(Data("X3LA".utf8)))
        XCTAssertNil(ListenProtocol.decode(Data([0x58, 0x33, 0x4C, 0x50, 9])), "other versions are ignored")
        var short = ListenProtocol.encode(.audio(.init(channels: 2, sequence: 1, sampleRate: 48000, samples: [1, 2, 3, 4])))
        short.removeLast(2)
        XCTAssertNil(ListenProtocol.decode(short), "truncated audio")
        XCTAssertNil(ListenProtocol.decode(OSCCodec.encode(OSCMessage("/xinfo"))))
    }

    func testInt16Clips() {
        XCTAssertEqual(ListenProtocol.int16(2), 32767)
        XCTAssertEqual(ListenProtocol.int16(-2), -32767)
        XCTAssertEqual(ListenProtocol.int16(0.5), 16384)
    }
}

final class JitterBufferTests: XCTestCase {
    private func packet(_ seq: UInt32, value: Int16, frames: Int = 240, channels: Int = 2) -> ListenProtocol.Audio {
        .init(channels: channels, sequence: seq, sampleRate: 48000, samples: [Int16](repeating: value, count: frames * channels))
    }

    func testWaitsForTheCushionThenPlays() {
        let jb = JitterBuffer(targetFrames: 480)
        jb.push(packet(0, value: 1000))
        XCTAssertEqual(jb.pull(240), [Float](repeating: 0, count: 480), "silent until 480 frames are in")
        XCTAssertFalse(jb.isPlaying)
        jb.push(packet(1, value: 1000))
        let out = jb.pull(240)
        XCTAssertEqual(out[0], 1000 / 32767, accuracy: 1e-6)
        XCTAssertTrue(jb.isPlaying)
        XCTAssertEqual(jb.buffered, 240)
    }

    func testMonoPlaysInBothEars() {
        let jb = JitterBuffer(targetFrames: 1)
        jb.push(packet(0, value: 2000, frames: 10, channels: 1))
        let out = jb.pull(1)
        XCTAssertEqual(out[0], out[1])
        XCTAssertGreaterThan(out[0], 0)
    }

    func testLatePacketsAreDroppedAndGapsKeepTime() {
        let jb = JitterBuffer(targetFrames: 240)
        jb.push(packet(10, value: 1))
        jb.push(packet(12, value: 3))   // 11 went missing: filled with silence
        XCTAssertEqual(jb.lostPackets, 1)
        XCTAssertEqual(jb.buffered, 720)
        jb.push(packet(11, value: 2))   // arrives too late
        XCTAssertEqual(jb.buffered, 720)
        let out = jb.pull(720)
        XCTAssertGreaterThan(out[0], 0)
        XCTAssertEqual(out[240 * 2], 0, "the gap is silent")
        XCTAssertGreaterThan(out[480 * 2], 0)
    }

    func testRunningDryRebuildsTheCushion() {
        let jb = JitterBuffer(targetFrames: 240)
        jb.push(packet(0, value: 5))
        _ = jb.pull(240)
        XCTAssertFalse(jb.pull(100).contains { $0 != 0 })
        XCTAssertEqual(jb.underruns, 1)
        XCTAssertFalse(jb.isPlaying)
    }

    func testFallingBehindSkipsAhead() {
        let jb = JitterBuffer(targetFrames: 480)
        for s in 0..<40 { jb.push(packet(UInt32(s), value: 7)) }   // a burst of 200 ms
        XCTAssertLessThanOrEqual(jb.buffered, 480 * 3 + 960 + 240)
        XCTAssertGreaterThanOrEqual(jb.buffered, 480)
    }

    func testLocalCaptureFeedsTheSameBuffer() {
        let jb = JitterBuffer(targetFrames: 64)
        let l = [Float](repeating: 0.25, count: 128), r = [Float](repeating: -0.25, count: 128)
        l.withUnsafeBufferPointer { lp in
            r.withUnsafeBufferPointer { rp in
                jb.push(left: lp.baseAddress!, right: rp.baseAddress!, frames: 128, sampleRate: 44100)
            }
        }
        XCTAssertEqual(jb.sampleRate, 44100)
        let out = jb.pull(64)
        XCTAssertEqual(out[0], 0.25)
        XCTAssertEqual(out[1], -0.25)
    }

    func testSequenceWraps() {
        let jb = JitterBuffer(targetFrames: 240)
        jb.push(packet(UInt32.max, value: 1))
        jb.push(packet(0, value: 1))
        XCTAssertEqual(jb.lostPackets, 0)
        XCTAssertEqual(jb.buffered, 480)
    }
}

final class ListenRoutingTests: XCTestCase {
    func testOutputs15And16ReachUSB31And32() {
        let p = ListenRouting.Plan(output: 15)
        XCTAssertEqual(p.usbLeft, 31)
        XCTAssertEqual(p.usbRight, 32)
        let c = Dictionary(p.changes.map { ($0.0, $0.1) }, uniquingKeysWith: { _, b in b })
        XCTAssertEqual(c["/outputs/main/15/src"], .int(74))
        XCTAssertEqual(c["/outputs/main/16/src"], .int(75))
        XCTAssertEqual(c["/config/routing/CARD/25-32"], .int(Int32(OutputRouting.digitalCodes.firstIndex(of: "OUT9-16")!)))
        XCTAssertTrue(p.isSet { c[$0] })
        XCTAssertFalse(p.isSet { _ in .int(0) })
    }

    func testOutputs7And8ReachUSB23And24() {
        let p = ListenRouting.Plan(output: 7)
        XCTAssertEqual(p.usbLeft, 23)
        XCTAssertEqual(p.cardBlockPath, "/config/routing/CARD/17-24")
    }
}
