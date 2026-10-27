import Foundation

// Helpers that do a sound engineer's routine jobs: finding feedback, setting gain, and giving a
// new channel a sensible starting point.

// MARK: - Feedback (ring-out)

/// Finds frequencies that are ringing in analyser frames: a narrow peak that stands well above
/// the bands around it, and keeps doing so for a few frames (music moves; feedback doesn't).
struct FeedbackDetector {
    struct Candidate: Identifiable, Equatable {
        let band: Int
        var level: Float
        /// How far the peak stands above the bands around it, in dB.
        var prominence: Float
        /// Seen in the latest frame.
        var live: Bool
        var id: Int { band }
        var frequency: Double { RTA.frequency(band) }
    }

    /// The most recent first; at most `maxCandidates`.
    private(set) var candidates: [Candidate] = []
    private var streak: [Int] = []

    /// A ringing band is at least this far above its neighbours…
    var minProminence: Float = 9
    /// …and at least this loud…
    var minLevel: Float = -60
    /// …for this many frames in a row (the desk sends about 20 a second).
    var framesToConfirm = 6
    var maxCandidates = 8

    mutating func ingest(_ levels: [Float]) {
        let n = levels.count
        guard n >= 13 else { return }
        if streak.count != n { streak = Array(repeating: 0, count: n) }
        var peaks: [Int: Float] = [:]
        for i in 0..<n {
            let v = levels[i]
            guard v.isFinite, v > minLevel else { continue }
            if i > 0 && levels[i - 1] > v { continue }
            if i < n - 1 && levels[i + 1] >= v { continue }
            // Bands 3 to 6 away on each side: about a third to two thirds of an octave.
            var around: [Float] = []
            for d in 3...6 {
                if i - d >= 0 { around.append(levels[i - d]) }
                if i + d < n { around.append(levels[i + d]) }
            }
            guard !around.isEmpty else { continue }
            let median = around.sorted()[around.count / 2]
            let prominence = v - median
            if prominence >= minProminence { peaks[i] = prominence }
        }
        for i in 0..<n {
            // A peak that wobbles by a band still counts as the same ring.
            let near = peaks[i] != nil || (i > 0 && peaks[i - 1] != nil) || (i < n - 1 && peaks[i + 1] != nil)
            streak[i] = near ? streak[i] + 1 : 0
        }
        for c in candidates.indices { candidates[c].live = false }
        for (i, prominence) in peaks where streak[i] >= framesToConfirm {
            if let c = candidates.firstIndex(where: { abs($0.band - i) <= 1 }) {
                candidates[c].level = levels[i]
                candidates[c].prominence = prominence
                candidates[c].live = true
            } else {
                candidates.insert(Candidate(band: i, level: levels[i], prominence: prominence, live: true), at: 0)
            }
        }
        if candidates.count > maxCandidates {
            candidates.removeLast(candidates.count - maxCandidates)
        }
    }

    mutating func dismiss(_ band: Int) {
        candidates.removeAll { $0.band == band }
    }

    mutating func reset() {
        candidates = []
        streak = []
    }
}

enum RingOut {
    /// Depth of the first cut, and of each extra tap.
    static let firstCut: Float = -6
    static let extraCut: Float = -3
    /// Narrow enough to leave the rest of the mix alone.
    static let notchQ: Float = 8
    /// A band this close (in octaves) is treated as the same frequency.
    static let sameFrequency: Float = 1.0 / 6

    enum Outcome: Equatable {
        /// Changes to make, and what they do ("Cut 2.9 kHz by 6 dB on EQ band 3").
        case changes([(String, OSCArg)], String)
        /// Every EQ band on the strip is already in use.
        case noFreeBand
        /// The band is already cut as far as it goes.
        case atLimit
        /// The strip's EQ hasn't been read yet.
        case unknown([String])

        static func == (a: Outcome, b: Outcome) -> Bool {
            switch (a, b) {
            case (.noFreeBand, .noFreeBand), (.atLimit, .atLimit): return true
            case let (.unknown(x), .unknown(y)): return x == y
            case let (.changes(x, s), .changes(y, t)): return s == t && x.map(\.0) == y.map(\.0) && x.map(\.1) == y.map(\.1)
            default: return false
            }
        }
    }

    static func arg(_ spec: ParamSpec, _ value: Float) -> OSCArg {
        .float(spec.quantize(spec.norm(value)))
    }

    /// What to change on `strip`'s EQ to notch out `frequency`: deepen a notch that's already
    /// there, or turn an unused band into a narrow cut. Never touches a band that's doing
    /// something else (a low cut, a shelf, or a boost).
    static func notch(_ strip: StripID, frequency: Double, value: (String) -> OSCArg?) -> Outcome {
        guard strip.hasEQ else { return .noFreeBand }
        let bands = Array(1...strip.eqBandCount)
        var needed: [String] = []
        for b in bands {
            for f in ["type", "f", "g"] where value(strip.eqPath(b, f)) == nil {
                needed.append(strip.eqPath(b, f))
            }
        }
        guard needed.isEmpty else { return .unknown(needed) }

        func eqType(_ b: Int) -> Int { value(strip.eqPath(b, "type"))?.intValue ?? -1 }
        func hz(_ b: Int) -> Float { Specs.eqFreq.value(value(strip.eqPath(b, "f"))?.floatValue ?? 0.5) }
        func gain(_ b: Int) -> Float { Specs.eqGain.value(value(strip.eqPath(b, "g"))?.floatValue ?? 0.5) }
        let target = Float(frequency)
        let eqOn = (value(strip.eqOnPath)?.intValue ?? 1) != 0
        var changes: [(String, OSCArg)] = []
        if !eqOn { changes.append((strip.eqOnPath, .int(1))) }

        // 1. A cut already near this frequency: make it deeper.
        if let b = bands.first(where: { b in
            (eqType(b) == 2 || eqType(b) == 3) && gain(b) < -0.4 && abs(log2f(hz(b) / target)) <= sameFrequency
        }) {
            let current = gain(b)
            guard current > -14.9 else { return .atLimit }
            let next = max(-15, current + extraCut)
            changes.append((strip.eqPath(b, "g"), arg(Specs.eqGain, next)))
            return .changes(changes, "Cut \(Self.label(target)) to \(Int(next.rounded())) dB on EQ band \(b)")
        }
        // 2. A band that isn't doing anything (flat). Inner bands first: the outer ones are
        //    usually the low and high cuts or shelves.
        let order = bands.count > 2 ? Array(bands.dropFirst().dropLast()) + [bands.first!, bands.last!] : bands
        guard let b = order.first(where: { b in
            let t = eqType(b)
            let flat = abs(gain(b)) < 0.4
            // Cuts and shelves at 0 dB do nothing either, except the low/high cut types.
            return flat && t != 0 && t != 5 && t <= 5
        }) else { return .noFreeBand }
        changes.append((strip.eqPath(b, "type"), .int(2)))
        changes.append((strip.eqPath(b, "f"), arg(Specs.eqFreq, target)))
        changes.append((strip.eqPath(b, "q"), arg(Specs.eqQ, notchQ)))
        changes.append((strip.eqPath(b, "g"), arg(Specs.eqGain, firstCut)))
        return .changes(changes, "Cut \(Self.label(target)) by \(Int(-firstCut)) dB on EQ band \(b)")
    }

    struct Notch: Identifiable, Equatable {
        let band: Int
        let hz: Float
        let gain: Float
        var id: Int { band }
    }

    /// The notches (narrow cuts) on a strip's EQ, for listing and undoing.
    static func notches(_ strip: StripID, value: (String) -> OSCArg?) -> [Notch] {
        guard strip.hasEQ else { return [] }
        return (1...strip.eqBandCount).compactMap { b in
            guard let t = value(strip.eqPath(b, "type"))?.intValue, t == 2 || t == 3,
                  let f = value(strip.eqPath(b, "f"))?.floatValue,
                  let g = value(strip.eqPath(b, "g"))?.floatValue,
                  let q = value(strip.eqPath(b, "q"))?.floatValue else { return nil }
            let gain = Specs.eqGain.value(g)
            // Narrow (Q 4 or more) cuts only: a broad cut is tone shaping, not a notch.
            guard gain < -0.4, Specs.eqQ.value(q) >= 4 else { return nil }
            return Notch(band: b, hz: Specs.eqFreq.value(f), gain: gain)
        }
    }

    static func label(_ hz: Float) -> String {
        hz >= 1000 ? String(format: hz >= 10000 ? "%.0f kHz" : "%.2g kHz", hz / 1000) : String(format: "%.0f Hz", hz)
    }
}

// MARK: - Gain

enum GainWizard {
    /// Where the loudest moment should land: 12 dB of headroom above it, the usual live target.
    static let targetPeak: Float = -12
    /// Below this nothing was heard (no signal, a dead cable, or phantom power off).
    static let silence: Float = -70
    static let listenSeconds: Double = 8

    enum Result: Equatable {
        case silent
        /// The new gain in dB, and whether the input clipped while listening.
        case set(gain: Float, clipped: Bool)
    }

    static func suggestion(currentGain: Float, peak: Float) -> Result {
        guard peak.isFinite, peak > silence else { return .silent }
        let clipped = peak >= -0.5
        // A clipped peak hides how loud it really was: take off a bit more than the maths says.
        let change = targetPeak - peak - (clipped ? 6 : 0)
        let raw = min(max(currentGain + change, -12), 60)
        return .set(gain: (raw * 2).rounded() / 2, clipped: clipped)
    }
}

// MARK: - Starting points

/// Built-in channel settings for common sources: a sensible low cut, gate, EQ and compressor to
/// start from. They load like presets (and undo the same way).
enum StarterPresets {
    struct Band {
        let type: Int
        let hz: Float
        let gain: Float
        let q: Float
        static func peq(_ hz: Float, _ gain: Float, q: Float = 1.4) -> Band { Band(type: 2, hz: hz, gain: gain, q: q) }
        static func lowShelf(_ hz: Float, _ gain: Float) -> Band { Band(type: 1, hz: hz, gain: gain, q: 1.4) }
        static func highShelf(_ hz: Float, _ gain: Float) -> Band { Band(type: 4, hz: hz, gain: gain, q: 1.4) }
        static func highCut(_ hz: Float) -> Band { Band(type: 5, hz: hz, gain: 0, q: 1.4) }
    }

    struct Gate {
        var mode = 3          // GATE
        var threshold: Float
        var range: Float
        var attack: Float = 0.5
        var hold: Float = 50
        var release: Float = 200
    }

    struct Comp {
        var threshold: Float
        var ratio: Float
        var knee: Float = 2
        var attack: Float = 10
        var release: Float = 120
        var makeup: Float = 0
    }

    struct Starter: Identifiable {
        let name: String
        let symbol: String
        let lowCut: Float
        var slope = 1          // 18 dB/oct
        let gate: Gate?
        let eq: [Band]
        let comp: Comp?
        var id: String { name }
    }

    static let all: [Starter] = [
        Starter(name: "Lead vocal", symbol: "music.mic", lowCut: 100, slope: 2, gate: nil,
                eq: [.peq(250, -2), .peq(500, -2, q: 2), .peq(3000, 2, q: 1.5), .highShelf(10000, 3)],
                comp: Comp(threshold: -20, ratio: 4, attack: 10, release: 120, makeup: 4)),
        Starter(name: "Backing vocal", symbol: "music.mic", lowCut: 150, slope: 2, gate: nil,
                eq: [.peq(250, -3), .peq(500, -2, q: 2), .peq(3000, 1), .highShelf(10000, 2)],
                comp: Comp(threshold: -18, ratio: 3, attack: 10, release: 120, makeup: 3)),
        Starter(name: "Speech", symbol: "person.wave.2", lowCut: 120, slope: 2,
                gate: Gate(mode: 1, threshold: -55, range: 12, attack: 2, hold: 100, release: 400),
                eq: [.peq(250, -3), .peq(600, -2, q: 2), .peq(3500, 3, q: 1.5), .highShelf(10000, 0)],
                comp: Comp(threshold: -22, ratio: 3, knee: 3, attack: 10, release: 150, makeup: 4)),
        Starter(name: "Kick", symbol: "circle.circle", lowCut: 40, gate: Gate(threshold: -40, range: 40, hold: 20, release: 150),
                eq: [.peq(60, 3), .peq(350, -5, q: 2), .peq(3500, 4, q: 1.5), .highShelf(8000, -2)],
                comp: Comp(threshold: -15, ratio: 4, attack: 15, release: 100, makeup: 2)),
        Starter(name: "Snare", symbol: "circle.dashed", lowCut: 90, gate: Gate(threshold: -35, range: 25, hold: 30, release: 200),
                eq: [.peq(200, 2, q: 1.5), .peq(800, -3, q: 2), .peq(5000, 3, q: 1.2), .highShelf(10000, 2)],
                comp: Comp(threshold: -18, ratio: 4, attack: 10, release: 120, makeup: 2)),
        Starter(name: "Toms", symbol: "circle.grid.2x1", lowCut: 60, gate: Gate(threshold: -40, range: 30, hold: 50, release: 300),
                eq: [.peq(100, 3), .peq(400, -5, q: 2), .peq(4000, 3), .highShelf(10000, -2)],
                comp: Comp(threshold: -15, ratio: 3, attack: 15, release: 150, makeup: 1)),
        Starter(name: "Overheads", symbol: "sparkles", lowCut: 150, gate: nil,
                eq: [.lowShelf(200, -2), .peq(500, -2, q: 1), .peq(3000, 0), .highShelf(10000, 2)],
                comp: nil),
        Starter(name: "Bass DI", symbol: "waveform.path", lowCut: 35, gate: nil,
                eq: [.peq(80, 2), .peq(250, -3, q: 1.5), .peq(800, 2, q: 1.5), .highShelf(5000, -3)],
                comp: Comp(threshold: -20, ratio: 4, attack: 20, release: 150, makeup: 3)),
        Starter(name: "Electric guitar", symbol: "guitars", lowCut: 100, gate: nil,
                eq: [.peq(200, -2), .peq(500, -2, q: 1.5), .peq(2500, 2, q: 1.2), .highCut(9000)],
                comp: Comp(threshold: -15, ratio: 2, attack: 20, release: 150, makeup: 1)),
        Starter(name: "Acoustic guitar", symbol: "guitars.fill", lowCut: 100, gate: nil,
                eq: [.peq(200, -3), .peq(800, -2, q: 1.5), .peq(5000, 2), .highShelf(10000, 2)],
                comp: Comp(threshold: -20, ratio: 3, attack: 15, release: 150, makeup: 2)),
        Starter(name: "Keys", symbol: "pianokeys", lowCut: 60, gate: nil,
                eq: [.peq(120, 0), .peq(300, -2, q: 1.5), .peq(3000, 0), .highShelf(10000, 1)],
                comp: Comp(threshold: -15, ratio: 2, attack: 20, release: 200, makeup: 1)),
        Starter(name: "Playback", symbol: "play.circle", lowCut: 30, slope: 0, gate: nil,
                eq: [.peq(120, 0), .peq(500, 0), .peq(3000, 0), .highShelf(10000, 0)],
                comp: nil),
    ]

    private static func index(_ v: Float, in list: [Float]) -> Int32 {
        Int32(list.enumerated().min { abs($0.element - v) < abs($1.element - v) }?.offset ?? 0)
    }

    /// The settings as a preset for a channel (paths relative to the strip).
    static func preset(_ s: Starter) -> ChannelPreset {
        let arg = RingOut.arg
        var v: [String: OSCArg] = [
            "/preamp/hpon": .int(1),
            "/preamp/hpf": arg(Specs.hpf, s.lowCut),
            "/preamp/hpslope": .int(Int32(s.slope)),
            "/eq/on": .int(1),
            "/gate/on": .int(s.gate == nil ? 0 : 1),
            "/dyn/on": .int(s.comp == nil ? 0 : 1),
        ]
        for (i, b) in s.eq.prefix(4).enumerated() {
            let n = i + 1
            v["/eq/\(n)/type"] = .int(Int32(b.type))
            v["/eq/\(n)/f"] = arg(Specs.eqFreq, b.hz)
            v["/eq/\(n)/g"] = arg(Specs.eqGain, b.gain)
            v["/eq/\(n)/q"] = arg(Specs.eqQ, b.q)
        }
        if let g = s.gate {
            v["/gate/mode"] = .int(Int32(g.mode))
            v["/gate/thr"] = arg(Specs.gateThreshold, g.threshold)
            v["/gate/range"] = arg(Specs.gateRange, g.range)
            v["/gate/attack"] = arg(Specs.attack, g.attack)
            v["/gate/hold"] = arg(Specs.hold, g.hold)
            v["/gate/release"] = arg(Specs.release, g.release)
        }
        if let c = s.comp {
            v["/dyn/mode"] = .int(0)
            v["/dyn/thr"] = arg(Specs.dynThreshold, c.threshold)
            v["/dyn/ratio"] = .int(index(c.ratio, in: X32Enums.ratioValues))
            v["/dyn/knee"] = arg(Specs.knee, c.knee)
            v["/dyn/attack"] = arg(Specs.attack, c.attack)
            v["/dyn/release"] = arg(Specs.release, c.release)
            v["/dyn/mgain"] = arg(Specs.makeup, c.makeup)
            v["/dyn/auto"] = .int(0)
        }
        let clip = ChannelClipboard(source: StripID(.channel, 1), sections: [.preamp, .gate, .eq, .comp], values: v)
        return ChannelPreset(name: s.name, clip: clip)
    }
}
