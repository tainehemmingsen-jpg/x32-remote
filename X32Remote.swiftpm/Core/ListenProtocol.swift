import Foundation

// Shared, word for word, with the Mac's X32 Listen Bridge (Mac/X32ListenBridge links to this
// file), so keep it to Foundation only.

// "Listen": hear the desk's solo bus on this iPad's earphones.
//
// The X32 doesn't send audio over the network, only over its USB card. So either the iPad is
// plugged into the desk's USB port (and reads two of the card's channels directly), or a Mac is
// plugged in and runs the small X32 Listen Bridge, which streams those two channels over Wi-Fi.
//
// The desk side is the same either way: the solo bus (Monitor L/R) goes to two local outputs,
// and those outputs go to the USB card, so they arrive on two of its channels.

/// The packets the Mac bridge and the iPad exchange (UDP, port 48032). Little-endian.
///
///     iPad -> Mac  "X3LP" v           probe: is a bridge there? (sent to every address on the subnet)
///     Mac -> iPad  "X3LI" v name      the bridge's answer, with the Mac's name
///     iPad -> Mac  "X3LH" v           hello: stream to me (repeated every second while listening)
///     iPad -> Mac  "X3LB" v           bye: stop streaming to me
///     Mac -> iPad  "X3LA" v ch frames(u16) seq(u32) rate(u32) samples(Int16 × frames × ch)
enum ListenProtocol {
    static let port: UInt16 = 48032
    static let version: UInt8 = 1
    /// How long the bridge keeps streaming without a hello.
    static let helloTimeout: TimeInterval = 5
    /// Frames per audio packet: 5 ms at 48 kHz.
    static let framesPerPacket = 240

    enum Message: Equatable {
        case probe
        case info(name: String)
        case hello
        case bye
        case audio(Audio)
    }

    struct Audio: Equatable {
        var channels: Int
        var sequence: UInt32
        var sampleRate: Int
        /// Interleaved samples.
        var samples: [Int16]

        var frames: Int { channels > 0 ? samples.count / channels : 0 }
    }

    private static let magics: [String: [UInt8]] = [
        "probe": Array("X3LP".utf8), "info": Array("X3LI".utf8), "hello": Array("X3LH".utf8),
        "bye": Array("X3LB".utf8), "audio": Array("X3LA".utf8),
    ]

    static func encode(_ message: Message) -> Data {
        var d = Data()
        func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        switch message {
        case .probe: d.append(contentsOf: magics["probe"]!); d.append(version)
        case .hello: d.append(contentsOf: magics["hello"]!); d.append(version)
        case .bye: d.append(contentsOf: magics["bye"]!); d.append(version)
        case .info(let name):
            d.append(contentsOf: magics["info"]!); d.append(version)
            d.append(contentsOf: Array(name.utf8.prefix(64)))
        case .audio(let a):
            d.append(contentsOf: magics["audio"]!); d.append(version)
            d.append(UInt8(clamping: a.channels))
            put16(UInt16(clamping: a.frames))
            put32(a.sequence)
            put32(UInt32(clamping: a.sampleRate))
            d.reserveCapacity(d.count + a.samples.count * 2)
            for s in a.samples { put16(UInt16(bitPattern: s)) }
        }
        return d
    }

    static func decode(_ data: Data) -> Message? {
        let b = [UInt8](data)
        guard b.count >= 5, b[4] == version else { return nil }
        let magic = Array(b[0..<4])
        func u16(_ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
        func u32(_ i: Int) -> UInt32 { UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24 }
        switch magic {
        case magics["probe"]!: return .probe
        case magics["hello"]!: return .hello
        case magics["bye"]!: return .bye
        case magics["info"]!: return .info(name: String(decoding: b[5...], as: UTF8.self))
        case magics["audio"]!:
            guard b.count >= 16 else { return nil }
            let channels = Int(b[5])
            let frames = Int(u16(6))
            let sequence = u32(8)
            let rate = Int(u32(12))
            let count = frames * channels
            guard channels >= 1, channels <= 2, rate >= 8000, rate <= 192_000, b.count >= 16 + count * 2 else { return nil }
            var samples = [Int16](repeating: 0, count: count)
            for i in 0..<count { samples[i] = Int16(bitPattern: u16(16 + i * 2)) }
            return .audio(Audio(channels: channels, sequence: sequence, sampleRate: rate, samples: samples))
        default:
            return nil
        }
    }

    /// Float samples (-1...1) to 16-bit, clipped.
    static func int16(_ f: Float) -> Int16 {
        Int16(max(-32767, min(32767, (f * 32767).rounded())))
    }
}

/// Smooths out Wi-Fi: packets go in as they arrive (late, early, missing), audio comes out at a
/// steady rate a little behind. Holds `target` of audio before it starts playing; if the network
/// stalls and it runs dry it plays silence and builds up again, and if it has drifted far behind
/// it skips ahead so the delay never creeps up. Safe to use from the network and audio threads.
final class JitterBuffer {
    private let lock = NSLock()
    /// Stereo frames, interleaved L R.
    private var ring: [Float]
    private let capacity: Int
    private var readIndex = 0
    private var count = 0
    private var expected: UInt32?
    private var playing = false

    /// Frames to hold before playing (and to fall back to after a stall).
    var targetFrames: Int {
        didSet { targetFrames = max(1, min(targetFrames, capacity / 2)) }
    }
    private(set) var sampleRate: Int = 48000
    /// How often it ran dry, and how many packets never arrived.
    private(set) var underruns = 0
    private(set) var lostPackets = 0

    init(capacityFrames: Int = 48000, targetFrames: Int = 1200) {
        capacity = capacityFrames
        ring = [Float](repeating: 0, count: capacityFrames * 2)
        self.targetFrames = max(1, min(targetFrames, capacityFrames / 2))
    }

    /// Frames waiting to be played.
    var buffered: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    var isPlaying: Bool {
        lock.lock(); defer { lock.unlock() }
        return playing
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        resetLocked()
    }

    private func resetLocked() {
        readIndex = 0
        count = 0
        expected = nil
        playing = false
    }

    /// Adds a packet. Mono is played in both ears.
    func push(_ audio: ListenProtocol.Audio) {
        lock.lock(); defer { lock.unlock() }
        if audio.sampleRate != sampleRate {
            sampleRate = audio.sampleRate
            resetLocked()
        }
        if let e = expected {
            let gap = Int32(bitPattern: audio.sequence &- e)
            if gap < 0 { return }                      // late: its moment has passed
            if gap > 0 {
                lostPackets += Int(gap)
                // Keep time across a short gap with silence; after a long one, start again.
                let missing = Int(gap) * audio.frames
                if missing > targetFrames * 4 {
                    resetLocked()
                } else {
                    appendSilence(missing)
                }
            }
        }
        expected = audio.sequence &+ 1
        let frames = audio.frames
        for f in 0..<frames {
            let l = Float(audio.samples[f * audio.channels]) / 32767
            let r = audio.channels > 1 ? Float(audio.samples[f * audio.channels + 1]) / 32767 : l
            append(l, r)
        }
        // Drifted well behind (the network caught up in a burst): skip to the target delay.
        if count > targetFrames * 3 + 960 {
            drop(count - targetFrames)
        }
    }

    /// Adds audio captured on this device (no network, so no sequence numbers). Allocates
    /// nothing, so it's safe to call from an audio callback.
    func push(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames: Int, sampleRate rate: Int) {
        lock.lock(); defer { lock.unlock() }
        if rate != sampleRate {
            sampleRate = rate
            resetLocked()
        }
        expected = nil
        for f in 0..<frames { append(left[f], right[f]) }
        if count > targetFrames * 3 + 960 {
            drop(count - targetFrames)
        }
    }

    /// Fills `frames` stereo frames (interleaved) for playback. Returns false when it played silence.
    @discardableResult
    func pull(_ frames: Int, into out: UnsafeMutablePointer<Float>) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if !playing {
            if count >= targetFrames { playing = true } else {
                for i in 0..<(frames * 2) { out[i] = 0 }
                return false
            }
        }
        let n = min(frames, count)
        for i in 0..<n {
            let idx = (readIndex + i) % capacity
            out[i * 2] = ring[idx * 2]
            out[i * 2 + 1] = ring[idx * 2 + 1]
        }
        readIndex = (readIndex + n) % capacity
        count -= n
        if n < frames {
            for i in (n * 2)..<(frames * 2) { out[i] = 0 }
            underruns += 1
            playing = false   // build up the cushion again before carrying on
            return false
        }
        return true
    }

    /// Convenience for tests.
    func pull(_ frames: Int) -> [Float] {
        var out = [Float](repeating: 0, count: frames * 2)
        out.withUnsafeMutableBufferPointer { _ = pull(frames, into: $0.baseAddress!) }
        return out
    }

    private func append(_ l: Float, _ r: Float) {
        if count >= capacity { drop(1) }
        let idx = (readIndex + count) % capacity
        ring[idx * 2] = l
        ring[idx * 2 + 1] = r
        count += 1
    }

    private func appendSilence(_ frames: Int) {
        for _ in 0..<frames { append(0, 0) }
    }

    private func drop(_ frames: Int) {
        let n = min(frames, count)
        readIndex = (readIndex + n) % capacity
        count -= n
    }
}
