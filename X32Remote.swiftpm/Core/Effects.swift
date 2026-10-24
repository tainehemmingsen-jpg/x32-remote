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
        return a
    }
}
