import Foundation

/// One step that can be undone: the values to put back.
struct UndoEntry: Equatable {
    struct Change: Equatable {
        let address: String
        let previous: OSCArg
    }

    var label: String
    var changes: [Change]
    var time: TimeInterval
}

/// The most recent changes made from this app, newest last.
final class UndoStack {
    private(set) var entries: [UndoEntry] = []
    let limit: Int
    /// Repeated changes to the same control within this many seconds count as one step
    /// (e.g. holding a + key, or tapping a switch on and off again).
    let coalesceWindow: TimeInterval

    init(limit: Int = 50, coalesceWindow: TimeInterval = 1.5) {
        self.limit = limit
        self.coalesceWindow = coalesceWindow
    }

    var isEmpty: Bool { entries.isEmpty }
    var last: UndoEntry? { entries.last }

    /// Records a single change from `previous` to `newValue`.
    func record(address: String, previous: OSCArg, newValue: OSCArg, label: String, now: TimeInterval) {
        if let lastEntry = entries.last, lastEntry.changes.count == 1, lastEntry.changes[0].address == address,
           now - lastEntry.time < coalesceWindow {
            if lastEntry.changes[0].previous == newValue {
                // Changed and changed back (e.g. a switch tapped twice): nothing left to undo.
                entries.removeLast()
            } else {
                // Keep the oldest value so undo goes back to where this burst started.
                entries[entries.count - 1].time = now
            }
            return
        }
        push(UndoEntry(label: label, changes: [UndoEntry.Change(address: address, previous: previous)], time: now))
    }

    func push(_ entry: UndoEntry) {
        guard !entry.changes.isEmpty else { return }
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    func popLast() -> UndoEntry? {
        entries.popLast()
    }

    func clear() {
        entries.removeAll()
    }
}

/// Human names for X32 addresses, e.g. "/ch/16/eq/2/g" -> "Ch 16 EQ 2 gain".
enum AddressNames {
    static func describe(_ address: String) -> String {
        if address.hasPrefix("/headamp/") {
            let parts = address.split(separator: "/")
            if parts.count >= 3, let n = Int(parts[1]) {
                return "\(StripID.headampLabel(n)) gain"
            }
            return "Gain"
        }
        let special = ["/config/solo/level": "Solo level", "/config/solo/dim": "Solo dim",
                       "/config/talk/A/level": "Talk A level", "/config/talk/B/level": "Talk B level"]
        if let name = special[address] { return name }
        let linkKinds = ["chlink": "Ch", "auxlink": "Aux", "fxlink": "FX", "buslink": "Mix", "mtxlink": "Mtx"]
        for (key, label) in linkKinds where address.hasPrefix("/config/\(key)/") {
            return "\(label) \(address.dropFirst("/config/\(key)/".count)) link"
        }
        if address.hasPrefix("/config/mute/") {
            return "Mute group " + String(address.dropFirst("/config/mute/".count))
        }
        guard let (strip, rest) = split(address) else { return address }
        return strip.footLabel + " " + parameterName(rest, strip: strip)
    }

    /// The strip an address belongs to, and the rest of the path ("/mix/fader").
    static func split(_ address: String) -> (StripID, String)? {
        let parts = address.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }
        let kinds: [String: StripKind] = ["ch": .channel, "auxin": .auxIn, "fxrtn": .fxReturn, "bus": .bus, "mtx": .matrix, "dca": .dca]
        if parts[0] == "main" {
            let strip = parts[1] == "m" ? StripID.monoC : StripID.mainLR
            return (strip, "/" + parts.dropFirst(2).joined(separator: "/"))
        }
        guard let kind = kinds[parts[0]], let n = Int(parts[1]), n >= 1, n <= kind.count else { return nil }
        return (StripID(kind, n), "/" + parts.dropFirst(2).joined(separator: "/"))
    }

    static func parameterName(_ rest: String, strip: StripID) -> String {
        let p = rest.split(separator: "/").map(String.init)
        guard let first = p.first else { return "" }
        let dynNames = ["thr": "threshold", "mgain": "gain", "on": "on", "ratio": "ratio", "knee": "knee", "attack": "attack",
                        "hold": "hold", "release": "release", "mix": "mix", "mode": "mode", "det": "detector", "env": "envelope",
                        "auto": "auto", "range": "depth"]
        switch first {
        case "mix":
            if p.count == 2 {
                switch p[1] {
                case "fader": return "fader"
                case "on": return "mute"
                case "pan": return "pan"
                case "st": return "LR assign"
                case "mono": return "mono assign"
                case "mlevel": return "mono level"
                default: return p[1]
                }
            }
            if p.count == 3, let n = Int(p[1]) {
                let target = strip.sendsFeedMatrix ? "Mtx \(n)" : "Mix \(n)"
                switch p[2] {
                case "level": return "send to \(target)"
                case "on": return "send on \(target)"
                case "pan": return "send pan \(target)"
                case "type": return "send tap \(target)"
                default: return p[2]
                }
            }
        case "fader": return "fader"
        case "on": return "mute"
        case "eq":
            if p.count == 2 && p[1] == "on" { return "EQ on" }
            if p.count == 3 {
                let field = ["f": "freq", "g": "gain", "q": "Q", "type": "type"][p[2]] ?? p[2]
                return "EQ \(p[1]) \(field)"
            }
        case "gate":
            if p.count == 2 { return "gate " + (dynNames[p[1]] ?? p[1]) }
        case "dyn":
            if p.count == 2 { return "comp " + (dynNames[p[1]] ?? p[1]) }
        case "preamp":
            if p.count == 2 {
                return ["trim": "trim", "invert": "polarity", "hpon": "low cut", "hpf": "low cut freq", "hpslope": "low cut slope"][p[1]] ?? p[1]
            }
        case "delay":
            if p.count == 2 { return p[1] == "on" ? "delay" : "delay time" }
        case "config":
            if p.count == 2 {
                return ["name": "name", "color": "colour", "source": "source"][p[1]] ?? p[1]
            }
        case "grp":
            if p.count == 2 { return p[1] == "dca" ? "DCA groups" : "mute groups" }
        default:
            break
        }
        return rest
    }
}
