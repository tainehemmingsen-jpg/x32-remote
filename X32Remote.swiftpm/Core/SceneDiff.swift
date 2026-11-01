import Foundation

/// "What changed since soundcheck": the differences between a saved scene and the desk now,
/// node by node, in words a person can read, each with the scene's line to put it back.
enum SceneDiff {
    struct Change: Identifiable, Equatable {
        /// The node path, e.g. "/ch/05/eq/2".
        let path: String
        /// "Lead Vox (Ch 5) · EQ band 2"
        let title: String
        /// What the scene had, and what the desk has now (values only).
        let saved: String
        let now: String
        /// The scene's line: sending it to the desk puts this back.
        let restoreLine: String
        var id: String { path }
    }

    /// Differences for the nodes in `scene` (nodes the desk didn't answer are left out).
    /// `names` gives a strip's name for nicer titles.
    static func changes(scene: [String], desk: [String], names: (StripID) -> String = { _ in "" }) -> [Change] {
        var deskByPath: [String: String] = [:]
        for line in desk { deskByPath[SceneFile.path(of: line)] = line }
        var out: [Change] = []
        for line in scene {
            let path = SceneFile.path(of: line)
            guard let current = deskByPath[path] else { continue }
            let a = SceneFile.tokens(line).values
            let b = SceneFile.tokens(current).values
            guard !same(a, b) else { continue }
            out.append(Change(path: path, title: title(for: path, names: names),
                              saved: a.joined(separator: " "), now: b.joined(separator: " "), restoreLine: line))
        }
        return out
    }

    /// Values match when every token matches, numbers within a hair (X32-Edit and the desk
    /// sometimes write the same number differently, like 0.0 and +0.0).
    static func same(_ a: [String], _ b: [String]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where x != y {
            if let fx = number(x), let fy = number(y), abs(fx - fy) < 0.011 { continue }
            return false
        }
        return true
    }

    private static func number(_ s: String) -> Double? {
        if s == "-oo" { return -1e9 }
        // The desk writes kHz values like "1k23" and "10k0".
        if let k = s.firstIndex(of: "k"), let whole = Double(s[..<k]) {
            let frac = String(s[s.index(after: k)...])
            return (whole + (Double("0." + frac) ?? 0)) * 1000
        }
        return Double(s.replacingOccurrences(of: "+", with: ""))
    }

    /// A readable name for a node path.
    static func title(for path: String, names: (StripID) -> String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard let head = parts.first else { return path }
        let kinds: [String: StripKind] = ["ch": .channel, "auxin": .auxIn, "fxrtn": .fxReturn, "bus": .bus, "mtx": .matrix, "dca": .dca]
        var strip: StripID?
        var rest = Array(parts.dropFirst())
        if let kind = kinds[head], let n = rest.first.flatMap({ Int($0) }) {
            strip = StripID(kind, n)
            rest.removeFirst()
        } else if head == "main" {
            strip = rest.first == "m" ? StripID.monoC : StripID.mainLR
            rest = Array(rest.dropFirst())
        }
        let what: String = {
            guard let first = rest.first else { return "On and level" }
            switch first {
            case "config": return "Name, colour and source"
            case "delay": return "Delay"
            case "preamp": return "Trim, polarity and low cut"
            case "gate": return rest.count > 1 ? "Gate key filter" : "Gate"
            case "dyn": return rest.count > 1 ? "Compressor key filter" : "Compressor"
            case "insert": return "Insert"
            case "eq": return rest.count > 1 ? "EQ band \(rest[1])" : "EQ on/off"
            case "mix":
                if rest.count > 1, let n = Int(rest[1]) { return "Send to Mix \(n)" }
                return "Fader, mute and pan"
            case "grp": return "DCA and mute groups"
            case "automix": return "Automix"
            default: return first
            }
        }()
        if let strip {
            let name = names(strip)
            let who = name.isEmpty ? strip.footLabel : "\(name) (\(strip.footLabel))"
            return "\(who) · \(what)"
        }
        switch head {
        case "fx": return "FX \(parts.count > 1 ? parts[1] : "") " + (parts.count > 2 ? (parts[2] == "par" ? "settings" : parts[2]) : "type")
        case "headamp": return "Preamp \(parts.count > 1 ? parts[1] : "") gain and 48V"
        case "outputs": return "Output patch " + parts.dropFirst().joined(separator: " ")
        case "config": return "Desk setup · " + parts.dropFirst().joined(separator: " ")
        default: return path
        }
    }
}
