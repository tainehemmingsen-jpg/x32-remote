import Foundation
import Observation

/// One console parameter, observed individually so only the views that read it redraw.
@Observable
final class Param {
    let address: String
    var value: OSCArg?

    /// While > 0 the user is dragging this control, so values arriving from the desk are ignored.
    @ObservationIgnored var touchCount: Int = 0

    init(address: String) {
        self.address = address
    }

    var float: Float { value?.floatValue ?? 0 }
    var int: Int { value?.intValue ?? 0 }
    var string: String { value?.stringValue ?? "" }
    var bool: Bool { int != 0 }
    var isKnown: Bool { value != nil }

    func float(or fallback: Float) -> Float { value?.floatValue ?? fallback }
    func int(or fallback: Int) -> Int { value?.intValue ?? fallback }
}

/// All console parameters the app has seen, keyed by OSC address.
final class ParamStore {
    private var params: [String: Param] = [:]

    func param(_ address: String) -> Param {
        if let existing = params[address] {
            return existing
        }
        let created = Param(address: address)
        params[address] = created
        return created
    }

    func value(_ address: String) -> OSCArg? {
        params[address]?.value
    }

    /// A value reported by the desk.
    func applyRemote(_ address: String, _ value: OSCArg) {
        let p = param(address)
        if p.touchCount > 0 { return }
        if p.value != value {
            p.value = value
        }
    }

    /// A value the user just set locally.
    func applyLocal(_ address: String, _ value: OSCArg) {
        let p = param(address)
        if p.value != value {
            p.value = value
        }
    }

    /// Forget everything (used when switching consoles).
    func clear() {
        for p in params.values where p.value != nil {
            p.value = nil
        }
    }
}

/// Live meter readings for one strip, in dB.
@Observable
final class MeterLevel {
    var level: Float = -90
    var level2: Float = -90
    var gateReduction: Float = 0
    var dynReduction: Float = 0
}

/// Converts /meters blobs into per-strip meter levels with simple ballistics.
final class MeterStore {
    private var levels: [StripID: MeterLevel] = [:]

    private static let block0Strips: [StripID] = {
        var list: [StripID] = []
        for kind in [StripKind.channel, .auxIn, .fxReturn, .bus, .matrix] {
            list.append(contentsOf: StripID.all(kind))
        }
        return list
    }()

    func meter(_ strip: StripID) -> MeterLevel {
        if let m = levels[strip] {
            return m
        }
        let m = MeterLevel()
        levels[strip] = m
        return m
    }

    func reset() {
        for m in levels.values {
            m.level = -90
            m.level2 = -90
            m.gateReduction = 0
            m.dynReduction = 0
        }
    }

    func ingest(block: Int, values: [Float]) {
        switch block {
        case 0:
            // 32 channels, 8 aux, 8 fx returns, 16 buses, 6 matrices
            for strip in MeterStore.block0Strips {
                if let i = strip.meters0Index, i < values.count {
                    setLevel(meter(strip), values[i])
                }
            }
        case 1:
            // 32 channel inputs, 32 gate gain reductions, 32 dynamics gain reductions
            guard values.count >= 96 else { return }
            for n in 1...32 {
                let m = meter(StripID(.channel, n))
                setReduction(m, gate: values[31 + n], dyn: values[63 + n])
            }
        case 2:
            // 16 buses, 6 matrices, main L, main R, mono, then dynamics gain reductions
            guard values.count >= 25 else { return }
            let main = meter(StripID.mainLR)
            setLevel(main, values[22], right: values[23])
            setLevel(meter(StripID.monoC), values[24])
            if values.count >= 49 {
                for n in 1...16 {
                    setReduction(meter(StripID(.bus, n)), gate: 1, dyn: values[24 + n])
                }
                for n in 1...6 {
                    setReduction(meter(StripID(.matrix, n)), gate: 1, dyn: values[40 + n])
                }
                setReduction(main, gate: 1, dyn: values[47])
                setReduction(meter(StripID.monoC), gate: 1, dyn: values[48])
            }
        default:
            break
        }
    }

    private func smoothed(current: Float, incoming: Float) -> Float {
        // Instant attack, ~30 dB/s release at 20 updates per second.
        if incoming >= current { return incoming }
        return max(incoming, current - 1.5)
    }

    private func setLevel(_ m: MeterLevel, _ amplitude: Float, right: Float? = nil) {
        let db = X32Math.amplitudeToDB(amplitude)
        let next = smoothed(current: m.level, incoming: db)
        if abs(next - m.level) >= 0.25 {
            m.level = next
        }
        if let r = right {
            let rdb = X32Math.amplitudeToDB(r)
            let nextR = smoothed(current: m.level2, incoming: rdb)
            if abs(nextR - m.level2) >= 0.25 {
                m.level2 = nextR
            }
        }
    }

    /// Gain-reduction meters are linear gain factors; 1.0 (or 0, when idle) means no reduction.
    private func reductionDB(_ g: Float) -> Float {
        if g <= 0 || g >= 0.999 { return 0 }
        return min(60, max(0, -20 * log10f(g)))
    }

    private func setReduction(_ m: MeterLevel, gate: Float, dyn: Float) {
        let g = reductionDB(gate)
        let d = reductionDB(dyn)
        if abs(g - m.gateReduction) >= 0.25 {
            m.gateReduction = g
        }
        if abs(d - m.dynReduction) >= 0.25 {
            m.dynReduction = d
        }
    }
}
