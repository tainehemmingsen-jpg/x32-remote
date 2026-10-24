import Foundation

/// The X32's eight effects slots. Slots 1-4 hold reverbs, delays and modulation effects (the ones
/// the app can edit); slots 5-8 hold EQs and processors (shown by name only).
enum Effects {
    static let slots = 1...8
    static let editableSlots = 1...4

    static func typePath(_ slot: Int) -> String { "/fx/\(slot)/type" }
    static func sourcePath(_ slot: Int, right: Bool = false) -> String { "/fx/\(slot)/source/\(right ? "r" : "l")" }
    static func parPath(_ slot: Int, _ n: Int) -> String { String(format: "/fx/%d/par/%02d", slot, n) }

    /// Short names for /fx/1-4/type, in desk order.
    static let typeCodes1: [String] = [
        "HALL", "AMBI", "RPLT", "ROOM", "CHAM", "PLAT", "VREV", "VRM",
        "GATE", "RVRS", "DLY", "3TAP", "4TAP", "CRS", "FLNG", "PHAS", "DIMC", "FILT",
        "ROTA", "PAN", "SUB", "D/RV", "CR/R", "FL/R", "D/CR", "D/FL", "MODD", "GEQ2",
        "GEQ", "TEQ2", "TEQ", "DES2", "DES", "P1A", "P1A2", "PQ5", "PQ5S", "WAVD",
        "LIM", "CMB", "CMB2", "FAC", "FAC1M", "FAC2", "LEC", "LEC2", "ULC", "ULC2",
        "ENH2", "ENH", "EXC2", "EXC", "IMG", "EDI", "SON", "AMP2", "AMP", "DRV2",
        "DRV", "PIT2", "PIT"
    ]

    /// Short names for /fx/5-8/type, in desk order.
    static let typeCodes2: [String] = [
        "GEQ2", "GEQ", "TEQ2", "TEQ", "DES2", "DES", "P1A", "P1A2",
        "PQ5", "PQ5S", "WAVD", "LIM", "FAC", "FAC1M", "FAC2", "LEC", "LEC2", "ULC",
        "ULC2", "ENH2", "ENH", "EXC2", "EXC", "IMG", "EDI", "SON", "AMP2", "AMP",
        "DRV2", "DRV", "PHAS", "FILT", "PAN", "SUB"
    ]

    /// Friendly names for the types the app can edit (indices 0-14 of slots 1-4).
    static let editableTypeNames: [String] = [
        "Hall Reverb", "Ambience", "Rich Plate", "Room Reverb", "Chamber", "Plate Reverb",
        "Vintage Reverb", "Vintage Room", "Gated Reverb", "Reverse Reverb", "Stereo Delay",
        "3-Tap Delay", "4-Tap Delay", "Stereo Chorus", "Stereo Flanger"
    ]

    static func typeName(slot: Int, type: Int) -> String {
        if slot <= 4 {
            if type >= 0 && type < editableTypeNames.count { return editableTypeNames[type] }
            if type >= 0 && type < typeCodes1.count { return typeCodes1[type] }
        } else if type >= 0 && type < typeCodes2.count {
            return typeCodes2[type]
        }
        return "Type \(type)"
    }

    // MARK: Tap tempo

    /// The delay-time parameter of the delay types (1-3000 ms), for tap tempo.
    static func tapTimeParameter(slot: Int, type: Int) -> Int? {
        guard editableSlots.contains(slot) else { return nil }
        switch type {
        case 10: return 2      // Stereo Delay: Mix, Time…
        case 11, 12: return 1  // 3-Tap, 4-Tap: Time first
        default: return nil
        }
    }

    /// 1-3000 ms in 1 ms steps.
    static let delayTimeSpec = ParamSpec(.linear(1, 3000), steps: 2999, unit: "ms", defaultNorm: 0.5)

    // MARK: Graphic EQs

    /// The 31 ISO third-octave bands of the graphic EQs.
    static let geqBands: [Float] = [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800,
                                    1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000]
    /// Each band and the master: -15…+15 dB in 0.5 dB steps.
    static let geqSpec = ParamSpec(.linear(-15, 15), steps: 60, unit: "dB", decimals: 1, defaultNorm: 0.5)

    /// How many independent graphic EQs a type holds: 2 for the dual GEQ/TEQ, 1 for the stereo
    /// ones, nil for everything else.
    static func graphicEQSides(slot: Int, type: Int) -> Int? {
        let base = slot <= 4 ? 27 : 0   // GEQ2, GEQ, TEQ2, TEQ
        switch type - base {
        case 0, 2: return 2
        case 1, 3: return 1
        default: return nil
        }
    }

    /// Parameter number of a band (1…31) on side 0 (A / stereo) or 1 (B).
    static func geqParNumber(side: Int, band: Int) -> Int { side * 32 + band }
    /// Parameter number of a side's master level.
    static func geqMasterNumber(side: Int) -> Int { side * 32 + 32 }

    private static let geqLabels = ["20", "25", "31.5", "40", "50", "63", "80", "100", "125", "160", "200", "250", "315",
                                    "400", "500", "630", "800", "1k", "1.25k", "1.6k", "2k", "2.5k", "3.15k", "4k", "5k",
                                    "6.3k", "8k", "10k", "12.5k", "16k", "20k"]

    static func geqBandLabel(_ i: Int) -> String {
        geqLabels.indices.contains(i) ? geqLabels[i] : ""
    }

    /// Strips whose insert is on and points at this slot (either side). `value` reads an int
    /// from the desk, nil if not read yet.
    static func insertedOn(slot: Int, value: (String) -> Int?) -> [StripID] {
        StripID.everything.filter { strip in
            guard strip.hasInsert, value(strip.insertPath("on")) == 1, let sel = value(strip.insertPath("sel")) else { return false }
            return sel == slot * 2 - 1 || sel == slot * 2
        }
    }

    /// How many /par/NN values a slot's current type uses (what to read when it's opened).
    static func parameterCount(slot: Int, type: Int) -> Int {
        if let sides = graphicEQSides(slot: slot, type: type) { return sides * 32 }
        return 16
    }

    /// "INS", "Mix 1"…"Mix 16", "M/C" for /fx/N/source/l.
    static func sourceName(_ v: Int) -> String {
        switch v {
        case 0: return "Insert"
        case 1...16: return "Mix \(v)"
        case 17: return "M/C"
        default: return "—"
        }
    }

    /// The mix bus feeding a slot, if it's fed from a bus (not an insert).
    static func feedingBus(sourceValue v: Int) -> Int? {
        (1...16).contains(v) ? v : nil
    }

    /// FX returns 1-8 carry slots 1-4 (two returns per slot: L and R).
    static func returnStrips(slot: Int) -> [StripID] {
        guard (1...4).contains(slot) else { return [] }
        return [StripID(.fxReturn, slot * 2 - 1), StripID(.fxReturn, slot * 2)]
    }

    /// One effect parameter.
    struct Param {
        enum Kind {
            /// A float sent as 0...1, shown in real units.
            case value(ParamSpec)
            /// An int choosing from a list.
            case choice([String])
            /// Shown as 0-100 % of its range (used where the desk's own range isn't certain).
            case percent
        }

        let number: Int
        let name: String
        let kind: Kind
    }

    private static func lin(_ lo: Float, _ hi: Float, _ unit: String, _ decimals: Int = 0) -> Param.Kind {
        .value(ParamSpec(.linear(lo, hi), steps: 1000, unit: unit, decimals: decimals, defaultNorm: 0.5))
    }

    private static func log(_ lo: Float, _ hi: Float, _ unit: String, _ decimals: Int = 0) -> Param.Kind {
        .value(ParamSpec(.logarithmic(lo, hi), steps: 1000, unit: unit, decimals: decimals, defaultNorm: 0.5))
    }

    private static let factors = ["1/4", "3/8", "1/2", "2/3", "1", "4/3", "3/2", "2", "3"]
    private static let offOn = ["Off", "On"]

    private static func params(_ list: [(String, Param.Kind)]) -> [Param] {
        list.enumerated().map { Param(number: $0.offset + 1, name: $0.element.0, kind: $0.element.1) }
    }

    /// Parameters for an editable type (nil for types the app doesn't edit).
    static func parameters(type: Int) -> [Param]? {
        let preDelay = ("Pre delay", lin(0, 200, "ms"))
        let damping = ("Damping", log(1000, 20000, "Hz"))
        let level = ("Level", lin(-12, 12, "dB", 1))
        let loCut = ("Low cut", log(10, 500, "Hz"))
        let hiCut = ("High cut", log(200, 20000, "Hz"))
        switch type {
        case 0, 5: // Hall, Plate
            return params([
                preDelay,
                ("Decay", type == 0 ? log(0.2, 5, "s", 2) : log(0.5, 10, "s", 2)),
                ("Size", lin(2, 100, "")),
                damping,
                ("Diffuse", lin(1, 30, "")),
                level, loCut, hiCut,
                ("Bass multiply", log(0.5, 2, "x", 2)),
                type == 0 ? ("Spread", lin(0, 50, "")) : ("Crossover", log(10, 500, "Hz")),
                type == 0 ? ("Shape", lin(0, 250, "")) : ("Modulation", lin(0, 50, "")),
                ("Mod speed", lin(0, 100, ""))
            ])
        case 1: // Ambience
            return params([
                preDelay,
                ("Decay", log(0.2, 7.3, "s", 2)),
                ("Size", lin(2, 100, "")),
                damping,
                ("Diffuse", lin(1, 30, "")),
                level, loCut, hiCut,
                ("Modulate", lin(0, 100, "")),
                ("Tail gain", lin(0, 100, ""))
            ])
        case 2, 3, 4: // Rich Plate, Room, Chamber
            let chamber = type == 4
            return params([
                preDelay,
                ("Decay", log(0.3, 29, "s", 2)),
                ("Size", type == 2 ? lin(4, 39, "") : lin(4, 76, "")),
                damping,
                ("Diffuse", lin(0, 100, "")),
                level, loCut, hiCut,
                ("Bass multiply", log(0.25, 4, "x", 2)),
                ("Spread", lin(0, 50, "")),
                type == 2 ? ("Attack", lin(0, 100, "")) : ("Shape", lin(0, 250, "")),
                ("Spin", lin(0, 100, "")),
                chamber ? ("Reflection L", lin(0, 500, "ms")) : ("Echo L", lin(0, 1200, "ms")),
                chamber ? ("Reflection R", lin(0, 500, "ms")) : ("Echo R", lin(0, 1200, "ms")),
                chamber ? ("Reflection gain L", lin(0, 100, "")) : ("Echo feed L", lin(-100, 100, "")),
                chamber ? ("Reflection gain R", lin(0, 100, "")) : ("Echo feed R", lin(-100, 100, ""))
            ])
        case 6: // Vintage Reverb
            return params([
                ("Pre delay", lin(0, 120, "ms")),
                ("Decay", log(0.3, 4.5, "s", 2)),
                ("Modulate", .percent),
                ("Vintage", .choice(offOn)),
                ("Position", .choice(["Front", "Rear"])),
                level, loCut,
                ("High cut", log(10000, 20000, "Hz")),
                ("Low multiply", log(0.5, 2, "x", 2)),
                ("High multiply", log(0.25, 1, "x", 2))
            ])
        case 7: // Vintage Room
            return params([
                ("Reverb delay", .percent),
                ("Decay", log(0.1, 20, "s", 2)),
                ("Size", .percent),
                ("Density", lin(1, 30, "")),
                ("Early level", .percent),
                level,
                ("Low multiply", log(0.1, 10, "x", 2)),
                ("High multiply", log(0.1, 10, "x", 2)),
                loCut, hiCut,
                ("Early left", .percent),
                ("Early right", .percent),
                ("Freeze", .choice(offOn))
            ])
        case 8, 9: // Gated, Reverse
            var list: [(String, Param.Kind)] = [
                preDelay,
                ("Decay", lin(140, 1000, "ms")),
                type == 8 ? ("Attack", lin(0, 30, "")) : ("Rise", lin(0, 50, "")),
                type == 8 ? ("Density", lin(1, 50, "")) : ("Diffuse", lin(1, 30, "")),
                ("Spread", lin(0, 100, "")),
                level, loCut, hiCut,
                ("High shelf gain", lin(-30, 0, "dB", 1))
            ]
            if type == 8 { list.append(("Diffuse", lin(1, 30, ""))) }
            return params(list)
        case 10: // Stereo Delay
            return params([
                ("Mix", lin(0, 100, "%")),
                ("Time", lin(1, 3000, "ms")),
                ("Mode", .choice(["Stereo", "Cross", "Mono"])),
                ("Factor L", .choice(factors)),
                ("Factor R", .choice(factors)),
                ("Offset L/R", lin(-100, 100, "")),
                loCut, hiCut,
                ("Feed low cut", log(10, 500, "Hz")),
                ("Feed L", lin(0, 100, "%")),
                ("Feed R", lin(0, 100, "%")),
                ("Feed high cut", log(200, 20000, "Hz"))
            ])
        case 11: // 3-Tap
            return params([
                ("Time", lin(1, 3000, "ms")),
                ("Gain", lin(0, 100, "%")),
                ("Pan", lin(-100, 100, "")),
                ("Feedback", lin(0, 100, "%")),
                loCut, hiCut,
                ("Factor A", .choice(factors)),
                ("Gain A", lin(0, 100, "%")),
                ("Pan A", lin(-100, 100, "")),
                ("Factor B", .choice(factors)),
                ("Gain B", lin(0, 100, "%")),
                ("Pan B", lin(-100, 100, "")),
                ("Cross feed", .choice(offOn)),
                ("Mono", .choice(offOn)),
                ("Dry", .choice(offOn))
            ])
        case 12: // 4-Tap
            return params([
                ("Time", lin(1, 3000, "ms")),
                ("Gain", lin(0, 100, "%")),
                ("Feedback", lin(0, 100, "%")),
                loCut, hiCut,
                ("Spread", lin(0, 6, "")),
                ("Factor A", .choice(factors)),
                ("Gain A", lin(0, 100, "%")),
                ("Factor B", .choice(factors)),
                ("Gain B", lin(0, 100, "%")),
                ("Factor C", .choice(factors)),
                ("Gain C", lin(0, 100, "%")),
                ("Cross feed", .choice(offOn)),
                ("Mono", .choice(offOn)),
                ("Dry", .choice(offOn))
            ])
        case 13: // Chorus
            return params([
                ("Speed", log(0.05, 5, "Hz", 2)),
                ("Depth L", lin(0, 100, "%")),
                ("Depth R", lin(0, 100, "%")),
                ("Delay L", log(0.5, 50, "ms", 1)),
                ("Delay R", log(0.5, 50, "ms", 1)),
                ("Mix", lin(0, 100, "%")),
                loCut, hiCut,
                ("Phase", lin(0, 180, "°")),
                ("Wave", lin(0, 100, "%")),
                ("Spread", lin(0, 100, "%"))
            ])
        case 14: // Flanger
            return params([
                ("Speed", log(0.05, 5, "Hz", 2)),
                ("Depth L", lin(0, 100, "%")),
                ("Depth R", lin(0, 100, "%")),
                ("Delay L", log(0.5, 20, "ms", 1)),
                ("Delay R", log(0.5, 20, "ms", 1)),
                ("Mix", lin(0, 100, "%")),
                loCut, hiCut,
                ("Phase", lin(0, 180, "°")),
                ("Feed low cut", log(10, 500, "Hz")),
                ("Feed high cut", log(200, 20000, "Hz")),
                ("Feed", lin(-90, 90, "%"))
            ])
        default:
            return nil
        }
    }

    /// Everything the effects page reads from the desk.
    static func addresses() -> [String] {
        var a: [String] = []
        for slot in slots {
            a.append(typePath(slot))
        }
        for slot in editableSlots {
            // Only slots 1-4 have a source (5-8 are always inserts).
            a.append(sourcePath(slot))
        }
        for slot in editableSlots {
            for n in 1...16 { a.append(parPath(slot, n)) }
        }
        // Where each slot is inserted.
        for strip in StripID.everything where strip.hasInsert {
            a.append(strip.insertPath("on"))
            a.append(strip.insertPath("sel"))
        }
        return a
    }
}

/// Works out a delay time from taps on a button: the average of the last few gaps, starting
/// again after a pause.
struct TapTempo {
    private(set) var taps: [TimeInterval] = []
    /// A gap longer than this starts a new count.
    var resetAfter: TimeInterval = 2.5
    var maxTaps = 5

    /// Records a tap. Returns the delay time in ms once there are two taps in a row.
    mutating func tap(at time: TimeInterval) -> Double? {
        if let last = taps.last, time - last > resetAfter || time <= last {
            taps.removeAll()
        }
        taps.append(time)
        if taps.count > maxTaps { taps.removeFirst(taps.count - maxTaps) }
        guard taps.count >= 2, let first = taps.first, let last = taps.last else { return nil }
        let ms = (last - first) / Double(taps.count - 1) * 1000
        return min(max(ms, 1), 3000)
    }

    static func bpm(ms: Double) -> Double { 60000 / ms }
}
