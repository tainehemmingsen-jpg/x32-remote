import Foundation

/// Parts of a channel that can be copied to another channel.
enum ProcessingSection: String, CaseIterable, Identifiable {
    case preamp, gate, eq, comp, sends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preamp: return "Preamp"
        case .gate: return "Gate"
        case .eq: return "EQ"
        case .comp: return "Compressor"
        case .sends: return "Sends"
        }
    }
}

extension StripID {
    func supports(_ section: ProcessingSection) -> Bool {
        !relativePaths(section).isEmpty
    }

    /// Paths below `base` that make up a section on this strip, e.g. "/eq/1/f".
    /// (Headamp gain belongs to the physical input, so it is never copied.)
    func relativePaths(_ section: ProcessingSection) -> [String] {
        var p: [String] = []
        switch section {
        case .preamp:
            if hasTrim { p.append("/preamp/trim") }
            if hasPolarity { p.append("/preamp/invert") }
            if hasHighPass { p += ["/preamp/hpon", "/preamp/hpf", "/preamp/hpslope"] }
            if hasDelay { p += ["/delay/on", "/delay/time"] }
        case .gate:
            if hasGate {
                p = ["on", "mode", "thr", "range", "attack", "hold", "release", "keysrc", "filter/on", "filter/type", "filter/f"].map { "/gate/" + $0 }
            }
        case .eq:
            if hasEQ {
                p.append("/eq/on")
                for b in 1...eqBandCount {
                    for f in ["type", "f", "g", "q"] { p.append("/eq/\(b)/\(f)") }
                }
            }
        case .comp:
            if hasDynamics {
                p = ["on", "mode", "det", "env", "thr", "ratio", "knee", "mgain", "attack", "hold", "release", "mix", "auto",
                     "pos", "filter/on", "filter/type", "filter/f"].map { "/dyn/" + $0 }
                if hasDynKeySource { p.append("/dyn/keysrc") }
            }
        case .sends:
            if sendCount > 0 {
                for n in 1...sendCount {
                    p.append(String(format: "/mix/%02d/level", n))
                    p.append(String(format: "/mix/%02d/on", n))
                    // Pan and tap point (pre/post) live on the odd send of each pair.
                    if n % 2 == 1 {
                        p.append(String(format: "/mix/%02d/pan", n))
                        p.append(String(format: "/mix/%02d/type", n))
                    }
                }
            }
        }
        return p
    }
}

/// Copied channel settings, kept as paths relative to the strip so they can go onto another one.
struct ChannelClipboard: Equatable {
    let source: StripID
    let sections: [ProcessingSection]
    let values: [String: OSCArg]

    /// Reads the sections from `value(for:)` (only values the app actually knows are copied).
    static func copy(from strip: StripID, sections: [ProcessingSection], value: (String) -> OSCArg?) -> ChannelClipboard {
        var values: [String: OSCArg] = [:]
        for section in sections {
            for rel in strip.relativePaths(section) {
                if let v = value(strip.base + rel) {
                    values[rel] = v
                }
            }
        }
        return ChannelClipboard(source: strip, sections: sections.filter { strip.supports($0) }, values: values)
    }

    /// The sections that can go onto `target`.
    func sections(for target: StripID) -> [ProcessingSection] {
        sections.filter { section in
            guard target.supports(section) else { return false }
            // Channel sends go to mix buses, bus sends go to matrices: never mix the two up.
            if section == .sends { return target.sendsFeedMatrix == source.sendsFeedMatrix }
            return true
        }
    }

    /// What to set on `target`: every copied value the target also has. EQ band types that only
    /// exist on 6-band EQs are left out when pasting onto a 4-band channel EQ.
    func changes(onto target: StripID) -> [(String, OSCArg)] {
        var out: [(String, OSCArg)] = []
        for section in sections(for: target) {
            for rel in target.relativePaths(section) {
                guard let v = values[rel] else { continue }
                if section == .eq, rel.hasSuffix("/type"), let t = v.intValue, t > 5, target.eqBandCount == 4 {
                    continue
                }
                out.append((target.base + rel, v))
            }
        }
        return out
    }
}
