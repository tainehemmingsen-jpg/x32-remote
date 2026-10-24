import Foundation
import Observation

/// The desk's real-time analyser: 100 bands from 20 Hz to 20 kHz on /meters/15, analysing
/// whichever strip /-prefs/rta/source points at.
enum RTA {
    static let block = 15
    static let bandCount = 100
    static let sourcePath = "/-prefs/rta/source"
    /// 0 = before the EQ, 1 = after it.
    static let positionPath = "/-prefs/rta/pos"
    static let screenPath = "/-stat/screen/screen"
    static let meterPagePath = "/-stat/screen/METER/page"
    /// /-stat/screen/screen value for METERS, and the RTA tab within it.
    static let metersScreen = 1
    static let rtaPage = 4
    /// Levels are clamped to this floor (the desk's own idle floor is about -97 dB).
    static let floorDB: Float = -90

    /// Centre frequency of band i (tenth-octave bands, 10 kHz at band 90).
    static func frequency(_ band: Int) -> Double {
        10000 * pow(2, Double(band - 90) / 10)
    }

    /// /-prefs/rta/source value for a strip: 0 off, 1 monitor, then channels, aux ins, FX
    /// returns, buses, matrices, LR and mono. DCAs have no audio.
    static func sourceValue(for strip: StripID) -> Int? {
        switch strip.kind {
        case .channel: return 1 + strip.index
        case .auxIn: return 33 + strip.index
        case .fxReturn: return 41 + strip.index
        case .bus: return 49 + strip.index
        case .matrix: return 65 + strip.index
        case .main: return 72
        case .mono: return 73
        default: return nil
        }
    }

    /// /meters/15 carries a count of 32-bit words followed by 16-bit little-endian levels in
    /// 1/256 dB (two bands per word).
    static func decode(_ blob: Data) -> [Float] {
        let bytes = [UInt8](blob)
        guard bytes.count >= 4 else { return [] }
        let words = Int(UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24)
        let n = max(0, min(words * 2, (bytes.count - 4) / 2, bandCount))
        var result: [Float] = []
        result.reserveCapacity(n)
        for i in 0..<n {
            let lo = UInt16(bytes[4 + i * 2])
            let hi = UInt16(bytes[5 + i * 2]) << 8
            result.append(Float(Int16(bitPattern: lo | hi)) / 256)
        }
        return result
    }

    static func encode(_ levels: [Float]) -> Data {
        var values = levels
        if values.count % 2 == 1 { values.append(-128) }
        var bytes: [UInt8] = []
        let words = UInt32(values.count / 2)
        bytes += [UInt8(words & 0xff), UInt8(words >> 8 & 0xff), UInt8(words >> 16 & 0xff), UInt8(words >> 24 & 0xff)]
        for v in values {
            let raw = UInt16(bitPattern: Int16(max(min(v * 256, 32767), -32768)))
            bytes += [UInt8(raw & 0xff), UInt8(raw >> 8)]
        }
        return Data(bytes)
    }
}

/// The latest analyser frame, with a gentle fall so it's readable.
@Observable
final class RTAData {
    private(set) var levels: [Float] = []
    private(set) var lastUpdate: TimeInterval = 0
    /// The desk keeps sending one unchanging flat frame until its analyser has been started
    /// (by showing its RTA page once after power-up).
    private(set) var idle = false

    @ObservationIgnored private var lastRaw: [Float] = []
    @ObservationIgnored private var sameFrames = 0

    func ingest(_ raw: [Float], now: TimeInterval) {
        guard !raw.isEmpty else { return }
        let flat = (raw.max() ?? 0) - (raw.min() ?? 0) < 0.01
        if flat && raw == lastRaw {
            sameFrames += 1
        } else {
            sameFrames = 0
        }
        lastRaw = raw
        let nowIdle = sameFrames >= 10
        if nowIdle != idle { idle = nowIdle }

        let clamped = raw.map { max($0, RTA.floorDB) }
        if levels.count != clamped.count {
            levels = clamped
        } else {
            // Instant rise, about 40 dB/s fall at 20 frames a second.
            levels = zip(levels, clamped).map { current, incoming in
                incoming >= current ? incoming : max(incoming, current - 2)
            }
        }
        lastUpdate = now
    }

    func reset() {
        levels = []
        lastRaw = []
        sameFrames = 0
        idle = false
        lastUpdate = 0
    }
}
